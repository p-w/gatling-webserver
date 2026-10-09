---
title: 'gatling-webserver: A minimal container image and reproducible energy benchmark for serving static research artefacts'
tags:
  - web server
  - containers
  - green software
  - energy efficiency
  - reproducibility
  - benchmarking
authors:
  - name: Peter Wilfahrt
    orcid: 0000-0000-0000-0000  # TODO: eigene ORCID eintragen
    affiliation: 1
affiliations:
  - name: Independent researcher, Germany  # TODO: Institution oder "Independent researcher" bestaetigen
    index: 1
date: 7 October 2026
bibliography: paper.bib
---

<!--
Entwurf. Alle mit TODO markierten Stellen brauchen echte Daten aus
benchmark/results/ oder eine Entscheidung der Autoren. JOSS verlangt
750 bis 1750 Woerter (ohne Front Matter und Literatur).
-->

# Summary

Research groups publish growing amounts of static material on the web: data
set landing pages, documentation, supplementary figures, trained-model
cards, and the HTML output of notebooks and static site generators. Most of
this is served by general-purpose web servers whose container images weigh
tens of megabytes and whose default configurations are tuned for dynamic
sites. `gatling-webserver` packages `gatling` [@gatling], a single-binary
HTTP server written by Felix von Leitner on top of the `dietlibc`
[@dietlibc] and `libowfat` [@libowfat] libraries, into an OCI container
image of a few megabytes, and adds a reproducible benchmark that measures
throughput, memory and electrical energy per served request against the
most widely used web server images. The project is aimed at researchers
and research software engineers who need to host static artefacts with a
minimal, auditable and low-energy footprint, and at anyone who wants to
quantify the energy cost of serving files from containers.

# Statement of need

Operational energy of information and communication technology is
estimated at 2 to 4 percent of global electricity use, with data transfer
and hosting as a substantial share [@freitag2021]. The Software Carbon
Intensity specification [@sci2024] asks software producers to report the
energy consumed per functional unit, such as per request. For web serving,
this number is rarely available: web server benchmarks report requests per
second and latency, while energy studies focus on programming languages
[@pereira2017] or on whole data centres. There is no small, reproducible
procedure that lets a research group answer the question "how many joules
does it cost to serve our documentation site, and would a different server
change that?".

`gatling-webserver` fills this gap in two ways. First, it provides a
hardened, ready-to-run image of a server that is already minimal by
construction: the `gatling` binary is statically linked against
`dietlibc`, has no configuration file, no scripting runtime and no
dependency on a system libc. Second, it ships the benchmark harness used
to evaluate that image, so that the energy claim can be checked and the
procedure can be reused for other servers or other workloads.

# State of the field

`nginx` [@nginx], Apache `httpd` [@httpd] and Caddy [@caddy] are the
dominant web servers for static content and are all available as official
container images. They are mature and flexible, but their images include a
full Alpine or Debian userland, a dynamic libc and configuration
machinery. Energy measurement tooling for containers exists in the form of
Kepler [@kepler] and Scaphandre [@scaphandre], which attribute RAPL energy
counters [@khan2018] to processes and containers, and load generators such
as `wrk` [@wrk] and `oha` [@oha] produce throughput and latency
distributions. What is missing is the combination: a fixed workload, a set
of comparable images, and a script that joins the load generator's request
count with the energy counter's joules into one figure of merit.

Building on `gatling` rather than contributing to one of the large
servers was a deliberate choice. The research question is what the lower
bound of resource use for static serving looks like, and that requires an
implementation that was designed for minimal size from the start.
`gatling` has been developed since 2003, is used as the reference server
in the `libowfat` ecosystem, and had no maintained container image before
this project.

# Software design

The image is built in two stages. The first stage fetches `dietlibc`,
`libowfat` and `gatling` from the upstream CVS repository and compiles a
static binary; the second stage copies only that binary and a small POSIX
shell entrypoint into a fresh Alpine base. The entrypoint encodes the
operating decisions that users of the raw binary get wrong most often:
`gatling` serves its working directory, so the entrypoint changes into a
dedicated document root, chroots into it after binding the ports, drops
privileges to an unprivileged user and disables the FTP and SMB protocols
that `gatling` would otherwise enable. All of this is controlled through
four environment variables and can be overridden for cases such as
FastCGI, where the PHP process must see the same file paths as the web
server and chroot has to be off.

Several properties of `gatling` are relevant to the research use case and
are documented in the repository because they differ from the behaviour
of mainstream servers: only world-readable files are served, which
prevents accidental publication; request paths containing `/.` are
rewritten so that dot-files are never reachable; and pre-compressed
`file.html.gz` variants are served transparently when the client accepts
gzip. The repository contains four
operating scenarios as `docker compose` stacks with smoke tests: static
files, WordPress behind `php-fpm`, a Tor onion service, and TLS
termination with Let's Encrypt via a reverse proxy.

# Reproducible benchmark

The benchmark in `benchmark/` compares the `gatling` image with the
official `nginx:alpine`, `httpd:alpine` and `caddy:alpine` images on
identical content: generated files of 1 KiB, 100 KiB and 10 MiB that
represent an HTML page, a figure and a data download. Each server is
started from the same compose file with its default static-file
configuration, warmed up, and then loaded with `oha` for a fixed duration
and concurrency per file size. During each run the harness records the
container's resident memory from `docker stats`, the image size, the
request count, throughput and latency percentiles from `oha`, and the
package energy from the Linux `powercap` interface, which exposes the
processor's RAPL counters [@khan2018]. Baseline energy of the idle host is
measured before each series and subtracted. The figure of merit is energy
per thousand requests, reported with the median and interquartile range of
five repetitions. `analyze.py` turns the raw CSV into the tables and
figures of this paper, so that every number can be regenerated with one
command on any Linux host with RAPL support.

<!-- TODO: Tabelle und Abbildung aus benchmark/results/ einfuegen, sobald
     Messungen vorliegen. Platzhalter: -->

| Image | Size (MiB) | RSS idle (MiB) | Requests/s (1 KiB) | J per 1000 req (1 KiB) |
|---|---|---|---|---|
| gatling-webserver | TODO | TODO | TODO | TODO |
| nginx:alpine | TODO | TODO | TODO | TODO |
| httpd:alpine | TODO | TODO | TODO | TODO |
| caddy:alpine | TODO | TODO | TODO | TODO |

Table: Benchmark summary. Median of five runs, `oha` with 64 connections
for 30 s per cell. Full results in `benchmark/results/`. \label{tab:bench}

![Energy per thousand requests by file size and server. \label{fig:energy}](figures/energy_per_1k.png){width="100%"}

Limitations are stated in the benchmark documentation: RAPL measures the
processor package and DRAM only, not network interfaces or the load
generator's own consumption when it runs on the same host; results are
therefore comparative, not absolute. The harness supports running the
load generator on a second machine to remove that confound.

# Research impact statement

<!-- TODO: JOSS verlangt belegte Nutzung, keine Absichtserklaerungen.
     Hier eintragen, was es wirklich gibt: Docker-Hub-Pulls mit Datum,
     Projekte oder Gruppen, die das Image einsetzen, Publikationen oder
     Lehrveranstaltungen, die den Benchmark verwendet haben. -->

The image has been published on Docker Hub since 2022 and is used by the
author to host static research and teaching material, including a Tor
onion service for a capture-the-flag course. TODO: add verifiable external
uses. The benchmark harness is designed as a template: exchanging the
compose service definitions is sufficient to compare other servers,
reverse proxies or application runtimes under the same energy
accounting, and we expect its main contribution to be enabling SCI-style
energy reporting [@sci2024] for research web infrastructure.

# AI usage disclosure

Portions of this manuscript, the benchmark harness and the repository
documentation were drafted with the assistance of Claude (Anthropic). The
assistant was used to summarise the `gatling` source code, to scaffold
shell and Python scripts and to draft prose. All generated content was
reviewed, tested where applicable and edited by the author, who takes
full responsibility for its correctness. No generative AI was used to
produce or alter measurement data.

# Acknowledgements

We thank Felix von Leitner for writing and maintaining `gatling`,
`dietlibc` and `libowfat` for more than two decades and for keeping them
freely available.

# References
