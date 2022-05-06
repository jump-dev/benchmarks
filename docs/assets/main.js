// Copyright (c) 2022: jump-dev/benchmarks contributors
//
// Use of this source code is governed by an MIT-style license that can be found
// in the LICENSE.md file or at https://opensource.org/licenses/MIT.

var d3 = Plotly.d3;

function load_json(filename, callback) {
    var xml_request = new XMLHttpRequest();
    xml_request.overrideMimeType("application/json");
    xml_request.open("GET", filename, true);
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

function normalize(x, unit_scale) {
    scale = 1 / unit_scale;
    // scale = 100 / x[0];
    // scale = 100 / x[x.length - 1];
    return x.map(xi => scale * xi);
}

function to_date(x) {
    return x.map(function (xi) {
        return xi.slice(0, 10) + ' ' + xi.slice(11, 13) + ':' + xi.slice(14, 16)
    });
}

function plot_chart(data, chart_key, unit_scale, y_label) {
    var chart = d3.select('#chart_' + chart_key).node();
    var series = Object.keys(data).map(function (key) {
        return {
            x: to_date(data[key]["dates"]),
            y: normalize(data[key][chart_key], unit_scale), 
            name: key,
        }
    });
    var layout = {
        margin: {b: 40, t: 20},
        hovermode: 'closest',
        yaxis: {title: y_label, type: 'log'},
        legend: {"orientation": "h"}
    }
    Plotly.plot(chart, series, layout);
    return chart;
}

function plot_summary_chart(data, series_info) {
    var chart = d3.select('#chart_summary' ).node();
    var series = series_info.map(function (item) {
        return {x: to_date(data["dates"]), y: data[item[0]], name: item[1]}
    });
    var layout = {
        margin: {b: 40, t: 20}, 
        hovermode: 'closest',
        yaxis: {title: 'Index (normalized to 100)', range: [0, 125]},
        legend: {"orientation": "h"}
    }
    Plotly.plot(chart, series, layout);
    return chart;
}

(function() {
    var charts = [];
    load_json("summary_data.json", function (data) {
        var chart = plot_summary_chart(
            data,
            [
                ['time_min', "Minimum wall time (seconds)"],
                ['time_median', "Median wall time (seconds)"],
                ['gc_min', "Minimum gc time (seconds)"],
                ['gc_median', "Median gc time (seconds)"],
                ['allocs', "# allocations"],
                ['memory', "Memory allocated"]
            ],
        )
        charts.push(chart);
        return
    });
    load_json("data.json", function (data) {
        charts.push(plot_chart(data, 'time_min', 1e9, "Wall time (seconds)"));
        charts.push(plot_chart(data, 'gc_min', 1e9, "Wall time (seconds)"));
        charts.push(plot_chart(data, 'allocs', 1, "Total allocations"));
        charts.push(plot_chart(data, 'memory', 1024 * 1024, "Memory allocated (MiB)"));
        return
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
