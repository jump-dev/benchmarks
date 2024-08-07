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
    all_repos, _ = GitHub.repos("jump-dev", auth = my_auth)
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
               row.status in (200, 301, 302)
    end
    return DataFrames.select(df, [:name, :date, :request_count])
end

function get_historical_downloads(
    filename::String = joinpath(DATA_DIR, "download_stats.json"),
)
    current = JSON.parsefile(filename; use_mmap = false)
    name = String[]
    date = Dates.Date[]
    request_count_sum = Int[]
    for (pkg, results) in current
        append!(name, fill("jump-dev/$pkg", length(results["requests"])))
        append!(date, Dates.Date.(results["dates"]))
        append!(request_count_sum, results["requests"])
    end
    return DataFrames.DataFrame(
        name = name,
        date = date,
        request_count_sum = request_count_sum,
    )
end

function get_pkg_uuids()
    pkg_uuids = Dict{String,String}()
    r = first(Pkg.Registry.reachable_registries())
    Pkg.Registry.create_name_uuid_mapping!(r)
    for (uuid, pkg) in r.pkgs
        Pkg.Registry.init_package_info!(pkg)
        url = replace(pkg.info.repo, "https://github.com/" => "")
        pkg_uuids["$uuid"] = replace(url, ".git" => "")
    end
    return pkg_uuids
end

function update_download_statistics()
    pkg_uuids = get_pkg_uuids()
    df = load_stats("package_requests_by_region_by_date", pkg_uuids)
    new_df = sort!(combine(groupby(df, [:name, :date]), :request_count => sum))
    new_df.name = String.(new_df.name)
    current = get_historical_downloads()
    append!(current, new_df)
    unique!(current)
    sort!(current, [:name, :date])
    data = Dict{String,Dict{String,Any}}()
    for g in groupby(current, :name)
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

function update_contributor_prs_over_time()
    data = JSON.parsefile(joinpath(DATA_DIR, "data.json"))
    # Compute the number of PRs per month
    all_prs = Dict{String,Int}()
    for (pkg, pkg_data) in data
        for item in pkg_data
            if item["is_pr"] && item["type"] == "opened"
                key = String(item["date"][1:7])
                all_prs[key] = get(all_prs, key, 0) + 1
            end
        end
    end
    # Find the earliest date of each contributor
    first_prs = Dict{String,String}()
    for (pkg, pkg_data) in data
        for item in pkg_data
            if item["is_pr"] && item["type"] == "opened"
                date = get(first_prs, item["user"], "9999-99")
                key = String(item["date"][1:7])
                if key < date
                    first_prs[item["user"]] = key
                end
            end
        end
    end
    # Compute the number of PRs by users in their first month
    new_prs = Dict{String,Int}()
    for (pkg, pkg_data) in data
        for item in pkg_data
            if item["is_pr"] && item["type"] == "opened"
                key = String(item["date"][1:7])
                if first_prs[item["user"]] == key
                    new_prs[key] = get(new_prs, key, 0) + 1
                end
            end
        end
    end
    dates = sort(collect(union(keys(all_prs), keys(new_prs))))
    counts = [(get(all_prs, date, 0), get(new_prs, date, 0)) for date in dates]
    open(joinpath(DATA_DIR, "contributor_prs_over_time.json"), "w") do io
        return write(io, JSON.json(Dict("dates" => dates, "counts" => counts)))
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
                if user in
                   ("github-actions[bot]", "JuliaTagBot", "femtocleaner[bot]")
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

function state_of_jump_statistics()
    old_date = Dates.today() - Dates.Year(1)
    # Downloads
    df = get_historical_downloads()
    n_downloads = sum(df[df.date.>=old_date, :].request_count_sum)
    # PRs and issues
    data = JSON.parsefile(joinpath(DATA_DIR, "data.json"))
    prs_opened, issues_opened, contributors = 0, 0, Set{String}()
    for (pkg, items) in data, item in items
        if Dates.DateTime(item["date"]) >= old_date && item["type"] == "opened"
            if item["is_pr"]
                push!(contributors, item["user"])
                prs_opened += 1
            else
                issues_opened += 1
            end
        end
    end
    open(joinpath(DATA_DIR, "summary.json"), "w") do io
        summary = Dict(
            "n_downloads" => n_downloads,
            "prs_opened" => prs_opened,
            "issues_opened" => issues_opened,
            "num_contributors" => length(contributors),
        )
        write(io, JSON.json(summary))
        return
    end
    println("""
    Downloads            : >$n_downloads
    Pull requests opened : $prs_opened
    Issues opened        : $issues_opened
    Unique contributors  : $(length(contributors))
    """)
    return
end

has_arg(arg) = any(isequal(arg), ARGS)

if has_arg("--update")
    update_download_statistics()
    update_package_statistics()
    update_contributor_prs_over_time()
    state_of_jump_statistics()
end
