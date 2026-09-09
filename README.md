
# Dashboard HPC

A monitoring dashboard for the HPC cluster, providing real-time and historical insights into job activity, disk usage, queue behavior, host resource utilization, and job efficiency.

## 📋 Overview

This dashboard consolidates key HPC operational metrics into a single view, helping track cluster health, job throughput, and resource efficiency across users, queues, and nodes.

## 🎯 Panels

### Job Status
- Visualizes running vs. pending jobs per user
- Includes time series and gauges for metrics like throughput and success rate over a 1-day range

### Disk State
- Separate panels for three filesets: `/work`, `/data`, and `home`
- Provides detailed insights on disk usage per fileset

### Queues State
- Bar chart showing pending vs. running jobs per queue
- Table of queue details
- Time series of pending jobs per queue over time

### Hosts
- Seven panels displaying used slots and CPU per node
- Includes time series and scatter plots for deeper insights

### Memory & CPU Efficiency
- Shows efficiency metrics for jobs submitted within the last 3 days
- Includes two gauges for average memory efficiency and average CPU efficiency

### Service Classes
- Panel for service class overview (currently pending HSM team approval)
- Once approved, this will provide insights across different service classes

## 🔧 Requirements

*(Add your stack here — e.g. Grafana version, data source, scripts used to collect metrics)*

## 🚀 Usage

*(Add setup/run instructions here — e.g. how to launch the dashboard, configure data sources, or run the collection scripts)*

## 📊 Project Structure

```
dashboard_hpc/
├── dashboardwithoutvariables/   # Dashboard configuration/panels
├── scripts/                     # Data collection / processing scripts
└── README.md
```

## 🤝 Contributing

Contributions welcome! Please submit issues or pull requests.
