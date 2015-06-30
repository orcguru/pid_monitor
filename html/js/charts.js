(function() {
    "use strict";
    var xlabel,
        slave,
        run_id,
        time0 = -1,
        header_lines,
        data_dir,
        parse_summary_line = function(line) {
            return {
                x: line.run_id.split('=')[1].split('.')[0], //threads
                y: line.elapsed_time_sec
            };
        },
        parse_dstat_line = function(line, linenum, factor) {
            var day,
                month,
                time,
                arr,
                time_ms,
                err_str,
                i;

            try {
                day = line.time.split('-')[0];
                month = line.time.split('-')[1].split(' ')[0];
                time = line.time.split(' ')[1].split(':');
                arr = [];
                //time_str = "2015-" + month + '-' + day + ' ' + time
                time_ms = new Date("2015", month, day, time[0], time[1], time[2]);
                //console.log(time_str);
                //time_ms = Date.parse(time_str);
                // console.log(time_ms);
                if (time0 === -1) {
                    time0 = time_ms;
                }
                // console.log((time_ms - time0) / 1000);
                arr.push((time_ms - time0) / 1000);

                for (i = 3; i < arguments.length; i += 1) {
                    arr.push(factor * line[arguments[i]]);
                }
            } catch (err) {
                err_str = "Problem reading CSV file near line ";
                err_str += (linenum + header_lines) + '<br>';
                err_str += JSON.stringify(line) + "<br>" + err.message;
                $("#id_error").html(err_str);
            }
            return arr;
        },
        csv_chart = function(data, id, title, labels, ylabel) {
            //console.log('csv_chart');
            //console.log(data);
            var chart = new Dygraph(
                document.getElementById(id),
                data, {
                    labels: labels,
                    //http://colorbrewer2.org/  <- qualitative, 6 classes
                    colors: ['rgb(228,26,28)', 'rgb(55,126,184)', 'rgb(77,175,74)', 'rgb(152,78,163)', 'rgb(255,127,0)', 'rgb(141,211,199)'],
                    xlabel: "Elapsed time [ sec ]",
                    ylabel: ylabel,
                    strokeWidth: 2,
                    legend: 'always',
                    labelsDivWidth: 500,
                    title: title
                }
            );
            return chart;
        },
        load_dstat_csv = function() {
            var url = data_dir + run_id + '.' + slave + '.dstat.csv';
            $("#id_data_dir").attr("href", data_dir + "all_files.html");
            // console.log(url);
            //Read csv data
            $.ajax({
                type: "GET",
                url: url,
                dataType: "text",
                success: function(data) {
                    var i = 0,
                        flag = true,
                        lines = data.split('\n'),
                        labels,
                        header,
                        body,
                        csv_data,
                        cpu_data,
                        mem_data,
                        io_data,
                        net_data,
                        sys_data,
                        proc_data,
                        pag_data;

                    while (flag) {
                        // Skip first few lines of dstat file
                        if (lines[i].indexOf("system") !== -1) {
                            flag = false;
                        }
                        i += 1;
                    }
                    labels = lines[i];
                    header = lines.slice(0, i - 2);
                    body = lines.slice(i, lines.length);

                    header = header.join(['<br>']);
                    //$("#id_header").html(header);
                    header_lines = i; // Used in error message in parse_dstat_line()

                    time0 = -1;
                    csv_data = $.csv.toObjects(body.join(['\n']));
                    // console.log(csv_data);
                    cpu_data = csv_data.map(
                        function(x, i) {
                            return parse_dstat_line(x, i, 1, "usr", "sys", "idl", "wai", "hiq", "siq");
                        }
                    );
                    mem_data = csv_data.map(
                        function(x, i) {
                            return parse_dstat_line(x, i, 1e-9, "used", "buff", "cach", "free");
                        }
                    );
                    io_data = csv_data.map(
                        function(x, i) {
                            return parse_dstat_line(x, i, 1e-6, "read", "writ");
                        }
                    );
                    net_data = csv_data.map(
                        function(x, i) {
                            return parse_dstat_line(x, i, 1e-6, "recv", "send");
                        }
                    );
                    sys_data = csv_data.map(
                        function(x, i) {
                            return parse_dstat_line(x, i, 1, "int", "csw");
                        }
                    );
                    proc_data = csv_data.map(
                        function(x, i) {
                            return parse_dstat_line(x, i, 1, "run", "blk", "new");
                        }
                    );
                    pag_data = csv_data.map(
                        function(x, i) {
                            return parse_dstat_line(x, i, 1, "in", "out");
                        }
                    );

                    csv_chart(cpu_data, "id_cpu", "CPU", ["time", "user", "system", "idle", "wait", "hiq", "siq"], "Usage [ % ]");
                    csv_chart(mem_data, "id_mem", "Memory", ["time", "used", "buff", "cache", "free"], "Usage [ GB ]");
                    csv_chart(io_data, "id_io", "IO", ["time", "read", "write"], "Usage [ MB/s ]");
                    csv_chart(net_data, "id_net", "Network", ["time", "recv", "send"], "Usage [ MB/s ]");
                    csv_chart(sys_data, "id_sys", "System", ["time", "interrupts", "context switches"], "");
                    csv_chart(proc_data, "id_proc", "Processes", ["time", "run", "blk", "new"], "");
                    csv_chart(pag_data, "id_pag", "Paging", ["time", "in", "out"], "");
                },
                error: function(request, status, error) {
                    console.log(status);
                    console.log(error);
                }
            });
        },
        create_cluster_button = function(i, id) {
            var button_id = "cluster_button" + String(i),
                button = $('<button></button>', {
                    id: button_id,
                    text: id
                }).appendTo('#cluster_buttons').addClass('button');

            if (i === 0) {
                button.addClass('active');
            }
            $("#" + button_id).on('click', function() {
                var $this = $(this);
                $this.addClass('active');
                $this.siblings('button').removeClass('active');
                slave = id;
                setTimeout(function() {
                    load_dstat_csv();
                }, 500);
            });
        },
        create_button = function(i, id) {
            var button_id = "button" + String(i),
                button = $('<button></button>', {
                    id: button_id,
                    text: id
                }).appendTo('#buttons').addClass('button');

            if (i === 0) {
                button.addClass('active');
            }
            $("#" + button_id).on('click', function() {
                var $this = $(this);
                $this.addClass('active');
                $this.siblings('button').removeClass('active');
                run_id = id;
                setTimeout(function() {
                    load_dstat_csv();
                }, 500);
            });
        },
        create_buttons = function(slaves, run_ids) {
            var i;
            for (i in slaves) {
                create_cluster_button(i, slaves[i]);
            }
            for (i in run_ids) {
                create_button(i, run_ids[i]);
            }
        },
        summary_chart = function(data, id) {
            //console.log(id);
            //console.log(data);

            c3.generate({
                bindto: id,
                size: {
                    height: 400
                },
                data: {
                    json: data,
                    keys: {
                        x: 'x',
                        value: ['y']
                    },
                    names: {
                        y: 'Elapsed time [ sec ]'
                    },
                    type: "line"
                },
                grid: {
                    x: {
                        show: true
                    },
                    y: {
                        show: true
                    }
                },
                point: {
                    r: 5
                },
                axis: {
                    x: {
                        // type: 'category',
                        // min: 0,
                        //max: 100,
                        label: {
                            text: xlabel,
                            position: 'outer-right'
                        }
                    },
                    y: {
                        min: 0,
                        // max: 100,
                        label: {
                            text: 'Elapsed execution time [ seconds ]',
                            position: 'outer-middle'
                        }
                    },
                }
            });
        },
        load_summary = function() {
            //Read summary data and create charts
            $.ajax({
                type: "GET",
                url: "summary.csv",
                dataType: "text",
                success: function(data) {
                    var csv_data = $.csv.toObjects(data);
                    // console.log(csv_data);
                    csv_data = csv_data.map(parse_summary_line); // OPTIONALLY CUSTOMIZE EACH LINE
                    // console.log(csv_data);
                    setTimeout(function() {
                        summary_chart(csv_data, "#id_all_data");
                    });
                },
                error: function(request, status, error) {
                    console.log(error);
                }
            });
        },
        read_config = function() {

            $.ajax({
                type: "GET",
                url: "config.json",
                dataType: "json",
                success: function(data) {
                    console.log(data);
                    xlabel = data.xlabel;
                    data_dir = '../data/raw/';
                    if (data.hasOwnProperty('data_dir')) {
                        data_dir = data.data_dir;
                    }

                    $('#id_workload').text(data.description);
                    $('#id_title').text(data.workload);
                    $('#id_date').text(data.date);
                    slave = data.slaves[0];
                    run_id = data.run_ids[0];

                    load_dstat_csv();
                    create_buttons(data.slaves, data.run_ids);

                },
                error: function(request, status, error) {
                    console.log(error);
                }
            });
        };

    load_summary();
    read_config();

})();
