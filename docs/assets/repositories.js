// Copyright (c) 2022: jump-dev/benchmarks contributors
//
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE.md file or at https://opensource.org/licenses/MIT.

var d3 = Plotly.d3;

function load_json(filename, callback) {
    var xml_request = new XMLHttpRequest();
    xml_request.overrideMimeType("application/json");
    xml_request.open("GET", filename, true);
    // xml_request.setRequestHeader("Access-Control-Allow-Origin","*")
    xml_request.onreadystatechange = function() {
        if (xml_request.readyState == 4) {
            if (xml_request.status == "200" || xml_request.status == "0") {
                // Required use of an anonymous callback as .open will NOT
                // return a value but simply returns undefined in asynchronous
                // mode.
                callback(JSON.parse(xml_request.responseText));
            } else {
                console.log("error getting " + filename);
                console.log(xml_request);
            }
        }
    };
    xml_request.send(null);
}

function to_date(d) {
    function two_digit(x) {
        if (x < 10) {
            return "0" + x
        } else {
            return x
        }
    }
    return d.getFullYear() + "-" + two_digit(d.getMonth() + 1) + "-" + two_digit(d.getDate());
}

function flip_data_to_user(data) {
    var new_data = {};
    Object.keys(data).map(function (key) {
        x = data[key];
        if (x.length > 0) {
            x.map(function (item) {
                tmp = Object.assign({}, item);
                user = tmp["user"];
                tmp["user"] = key;
                if (!(user in new_data)) {
                    new_data[user] = [];
                }
                new_data[user].push(tmp);
                return
            });
        }
        return
    });
    Object.keys(new_data).map(function (key) {
        new_data[key].sort((a, b) => a["date"] >= b["date"]);
    })
    return new_data;
}

function add_new_dates(x, y, new_date, new_value) {
    if (x.length == 0) {
        x.push(new_date);
        y.push(new_value);
    } else if (x[x.length-1] == new_date) {
        y[y.length-1] = new_value;  // update in-place
    } else {
        var date = new Date(x[x.length-1]);
        new_date = new Date(new_date);
        while (date < new_date) {
            date.setDate(date.getDate() + 1);
            x.push(to_date(date));
            y.push(y[y.length-1]);
        }
        x.push(to_date(new_date));
        y.push(new_value);
    }
    return
}

function count_of_opened_issues(data, key, is_pr, is_cumulative, visible) {
    i = 0;
    x = [];
    y = [];
    data[key].map(function(item) {
        if (item["is_pr"] != is_pr) {
            return
        } else if (item["type"] == "opened") {
            i++;
            add_new_dates(x, y, item["date"].slice(0, 10), i);
        } else if (!is_cumulative) {
            i--;
            add_new_dates(x, y, item["date"].slice(0, 10), i);
        }
    });
    add_new_dates(x, y, to_date(new Date()), i);
    object = {name: key, "x": x, "y": y, stackgroup: "one"}
    if (!visible.has(key)) {
        object["visible"] = "legendonly";
    }
    return object
}

function count_of_users(data, key, is_pr, visible) {
    names = new Set();
    i = 0;
    x = [];
    y = [];
    data[key].map(function(item) {
        if (item["is_pr"] != is_pr || item["type"] == "closed") {
            return
        } else if (names.has(item["user"])) {
            return
        }
        names.add(item["user"]);
        i++;
        add_new_dates(x, y, item["date"].slice(0, 10), i);
    });
    add_new_dates(x, y, to_date(new Date()), i);
    object = {name: key, "x": x, "y": y}
    if (!visible.has(key)) {
        object["visible"] = "legendonly";
    }
    return object
}

function last(x) {
    return  x[x.length - 2];
}

(function() {
    var charts = [];
    layout = {
        margin: {b: 30, t: 20},
        hovermode: 'closest',
        "yaxis": {
            "range": ["2013-01-01", to_date(new Date())],
            "title": "Count"
        }
    }    
    load_json("download_stats.json", function (data) {
        var chart = d3.select('#chart_download_statistics').node();
        visible = new Set(["JuMP.jl", "MathOptInterface.jl", "MutableArithmetics.jl"]);
        total_downloads = {}
        Object.keys(data).map(function (key) {
            total_downloads[key] = data[key]["requests"].reduce((a, b) => a+b);
        })
        sorted_keys = Object.keys(data).sort(
            (a, b) => total_downloads[a] < total_downloads[b]
        )
        var series = sorted_keys.map(function (key) {
            object = {
                x: data[key]["dates"],
                y: data[key]["requests"],
                name: key,
            }
            if (!visible.has(key)) {
                object["visible"] = "legendonly"
            }
            return object
        });
        Plotly.plot(
            chart,
            series,
            {
                margin: {b: 40, t: 20},
                hovermode: 'closest',
                "yaxis": {
                    "range": ["2021-09-01", to_date(new Date())],
                    "title": "Download count"
                }
            },
        );
        charts.push(chart);
        return
    });
    load_json("data.json", function (data) {
        function plot_chart(data, key, f, compare = (a, b) => a >= b) {
            var chart = d3.select(key).node();
            var series = Object.keys(data).sort(compare).map(f);
            Plotly.plot(chart, series, layout);
            charts.push(chart);
            return
        }
        pkgs = new Set(["JuMP.jl", "MathOptInterface.jl"]);
        plot_chart(
            data,
            "#chart_count_open_issues", 
            key => count_of_opened_issues(data, key, false, false, pkgs),
            (a, b) => data[a].length > data[b].length,
        );
        plot_chart(
            data,
            "#chart_count_open_pull_requests", 
            key => count_of_opened_issues(data, key, true, false, pkgs),
            (a, b) => data[a].length > data[b].length,
        );
        plot_chart(
            data,
            "#chart_cumulative_count_open_issues", 
            key => count_of_opened_issues(data, key, false, true, pkgs),
            (a, b) => data[a].length > data[b].length,
        );
        plot_chart(
            data,
            "#chart_cumulative_count_open_pull_requests", 
            key => count_of_opened_issues(data, key, true, true, pkgs),
            (a, b) => data[a].length > data[b].length,
        );
        plot_chart(
            data,
            "#chart_count_users_open_issues", 
            key => count_of_users(data, key, false, pkgs),
            (a, b) => data[a].length < data[b].length,
        );
        plot_chart(
            data,
            "#chart_count_users_open_pull_requests", 
            key => count_of_users(data, key, true, pkgs),
            (a, b) => data[a].length < data[b].length,
        );
        user_data = flip_data_to_user(data);
        users = new Set(["odow", "mlubin", "blegat"]);
        plot_chart(
            user_data,
            "#chart_unique_users_open_issues", 
            key => count_of_opened_issues(user_data, key, false, true, users),
            (a, b) => user_data[a].length > user_data[b].length,
        );
        plot_chart(
            user_data,
            "#chart_unique_users_open_pull_requests", 
            key => count_of_opened_issues(user_data, key, true, true, users),
            (a, b) => user_data[a].length > user_data[b].length,
        );
    });
    /* =========================================================================
        Resizing stuff.
    ========================================================================= */
    window.onresize = function() {
        charts.map(function(chart){
            if (window.getComputedStyle(chart).display == "block") {
                Plotly.Plots.resize(chart)
            }
        })
    };
})();
