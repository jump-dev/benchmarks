# Copyright (c) 2022: jump-dev/benchmarks contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

import CSV
using DataFrames
import Dates
import Downloads
import GitHub
import JSON
import Pkg
import TOML

# Holds GitHub secrets. Not committed to the repository.
if isfile(joinpath(@__DIR__, "dev.env"))
    include("dev.env")
end

const DATA_DIR = joinpath(dirname(@__DIR__), "docs", "repositories")

function Repository(repo; since, until, my_auth)
    println("Getting : ", repo)
    return GitHub.issues(
        repo;
        auth = my_auth,
        params = Dict("state" => "all", "since" => since, "until" => until),
    )
end

function get_repos(since, until)
    my_auth = GitHub.authenticate(ENV["PERSONAL_ACCESS_TOKEN"])
    all_repos, _ = GitHub.repos("jump-dev", auth = my_auth);
    return Dict(
        repo => Repository(
            "jump-dev/" * repo;
            since = since,
            until = until,
            my_auth = my_auth,
        ) for repo in map(r -> "$(r.name)", all_repos)
    )
end

function download_stats(file)
    url = "https://julialang-logs.s3.amazonaws.com/public_outputs/current/$(file).csv.gz"
    output = joinpath(dirname(@__DIR__), "data", "$(file).csv.gz")
    Downloads.download(url, output)
    return output
end

function load_stats(file, uuids)
    out = download_stats(file)
    df = CSV.read(out, DataFrames.DataFrame)
    uuid_to_name = DataFrames.DataFrame(
        package_uuid = collect(keys(uuids)),
        name = collect(values(uuids)),
    )
    df = DataFrames.leftjoin(df, uuid_to_name; on = :package_uuid)
    filter!(df) do row
        return !ismissing(row.client_type) &&
               row.client_type == "user" &&
               !ismissing(row.name) &&
               occursin("jump-dev/", row.name) &&
               row.status == 200
    end
    return DataFrames.select(df, [:name, :date, :request_count])
end

function update_download_statistics()
    pkg_uuids = Dict{String,String}()
    depot = Pkg.depots1()
    for (root, dirs, files) in walkdir(joinpath(depot, "registries/General"))
        for dir in dirs
            file = joinpath(root, dir, "Package.toml")
            if !isfile(file)
                continue
            end
            data = TOML.parsefile(joinpath(root, dir, "Package.toml"))
            repo = replace(data["repo"], ".git" => "")
            pkg_uuids[data["uuid"]] = replace(repo, "https://github.com/" => "")
        end
    end
    df = load_stats("package_requests_by_region_by_date", pkg_uuids)
    new_df = sort!(combine(groupby(df, [:name, :date]), :request_count => sum))
    data = Dict{String,Dict{String,Any}}()
    for g in groupby(new_df, :name)
        key = replace(g[1, :name], "jump-dev/" => "")
        data[key] = Dict{String,Any}(
            "dates" => string.(collect(g.date)),
            "requests" => collect(g.request_count_sum),
        )
    end
    open(joinpath(DATA_DIR, "download_stats.json"), "w") do io
        return write(io, JSON.json(data))
    end
    return
end

function update_package_statistics()
    since = "2013-01-01T00:00:00"
    repos = get_repos(since, Dates.now())
    data = Dict()
    for (k, v) in repos
        if !(endswith(k, ".jl") || k in ("MathOptFormat",))
            continue
        end
        events = Dict{String,Any}[]
        map(v[1]) do issue
            event = Dict(
                "user" => issue.user.login,
                "is_pr" => issue.pull_request !== nothing,
                "type" => "opened",
                "date" => issue.created_at,
            )
            push!(events, event)
            if issue.closed_at !== nothing
                event = copy(event)
                event["type"] = "closed"
                event["date"] = issue.closed_at
                push!(events, event)
            end
            return
        end
        data[k] = sort!(events, by = x -> x["date"])
    end
    open(joinpath(DATA_DIR, "data.json"), "w") do io
        return write(io, JSON.json(data))
    end
    return
end

# This script was used to generate the list of contributors for the JuMP 1.0
# release. It may be helpful in future.
function print_all_contributors(; minimum_prs::Int = 1)
    data = JSON.parsefile(joinpath(DATA_DIR, "data.json"))
    prs_by_user = Dict{String,Int}()
    for (_, pkg_data) in data
        for item in pkg_data
            if item["is_pr"] && item["type"] == "opened"
                user = item["user"]
                if user in (
                    "github-actions[bot]",
                    "JuliaTagBot",
                    "femtocleaner[bot]",
                )
                    continue
                end
                if haskey(prs_by_user, user)
                    prs_by_user[user] += 1
                else
                    prs_by_user[user] = 1
                end
            end
        end
    end
    names = collect(keys(prs_by_user))
    sort!(names; by = name -> (-prs_by_user[name], name))
    for name in names
        if prs_by_user[name] >= minimum_prs
            println(" * [@$(name)](https://github.com/$(name))")
        end
    end
    return prs_by_user
end

function prs_by_user(user)
    data = JSON.parsefile(joinpath(DATA_DIR, "data.json"))
    prs_by_user = Any[]
    for (pkg, pkg_data) in data
        for item in pkg_data
            if item["user"] == user && item["is_pr"] && item["type"] == "opened"
                push!(prs_by_user, (pkg, item))
            end
        end
    end
    return prs_by_user
end

has_arg(arg) = any(isequal(arg), ARGS)

if has_arg("--update")
    update_download_statistics()
    update_package_statistics()
end
