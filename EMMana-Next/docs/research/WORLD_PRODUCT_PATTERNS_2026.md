# World product patterns for antenna/EM software — 2026 review

Purpose: extract product/workflow patterns for EMMana-Next without copying proprietary solver implementations.

## Japan

### MMANA / MMANA-GAL
The original Japanese MMANA was created by Makoto Mori (JE3HHT). Current MMANA-GAL exposes a table-based antenna editor, graphical antenna view, result comparison, frequency plots and automatic optimisation around impedance/SWR/gain/F-B/current objectives.

Reference: https://gal-ana.de/basicmm/en/index.htm

Product lesson for EMMana-Next:
- fast wire-antenna workflow matters;
- result comparison should be a first-class object;
- antenna templates and manual tuning after optimisation are valuable.

### Murata Software Femtet
Femtet combines 3D modeling, meshing, multiple physics solvers and results display. Its electromagnetic solver exposes S/Y/Z parameters, radiation characteristics and Touchstone export, and its examples include antennas with impedance-matching components and adaptive meshing.

References:
- https://www.muratasoftware.com/en/products/explanation/
- https://www.muratasoftware.com/en/products/mainhelp/mainhelp2025_0_en/desktop/Examples/Hertz/hertzofexampleslist.htm

Product lesson:
- materials/geometry/results belong to a guided project workflow;
- measured/circuit interoperability is part of the product, not an afterthought.

## China

### Xpeedic
Xpeedic separates a broad RF/EDA portfolio into 3D antenna EM (Hermes 3D), transient EM, RF system simulation (XDS), S-parameter post-processing (SnpExpert), automated measurement, process/data management (XPLM), job queue and library management.

References:
- https://www.xpeedic.com/products/?lang=en
- https://www.xpeedic.com/uploadfile/02026/0113/20260113102131761.pdf

Product lesson:
- solver, system design, post-processing, measurement, libraries and job management should be separate services/layers;
- EMMana-Next should keep the solver replaceable and grow the workflow around it.

## United States

### Ansys HFSS
HFSS Antenna Design Toolkit automates geometry, setup and reports for many antenna types and supports frequency-driven synthesis plus parametric sweeps/optimisation.

Reference: https://ansyshelp.ansys.com/public/Views/Secured/Electronics/v251/en/Subsystems/HFSS/Content/HFSS/HFSSAntennaDesignToolkit.htm

Product lesson:
- template + synthesis wizard is a high-value front door;
- generated designs should remain parameterized.

### Remcom XFdtd
XFdtd presents a clear workflow: project properties → geometry → materials → excitation → boundary → grid/mesh → sensors → simulation → results → post-processing → parameters/scripts. It also supports reusable libraries, custom project templates, matching-network/circuit post-processing and array optimisation.

References:
- https://www.remcom.com/applications/antenna-simulation-design-software
- https://www.remcom.com/xfdtd-3d-em-simulation-software

Product lesson:
- Analysis Plan should explicitly say what outputs are requested;
- post-processing and matching-network work should not contaminate the core EM model.

## Europe

### Dassault Systèmes CST Studio Suite
CST uses parameterized models, automatic local/global optimisation, matching circuits, an array wizard and System Assembly and Modeling (SAM) to split complex systems into components and use an appropriate solver for each component.

References:
- https://www.3ds.com/products/simulia/electromagnetic-simulation/antenna-design
- https://www.3ds.com/products/simulia/cst-studio-suite/workflow-integration
- https://www.3ds.com/products/simulia/cst-studio-suite/electromagnetic-systems-modeling

Product lesson:
- multi-backend solver selection belongs above the physical model;
- component decomposition and back-annotation are future architecture targets.

### WIPL-D (Serbia)
WIPL-D combines CAD/full-wave MoM workflows with an optimiser supporting Particle Swarm, Genetic, Simplex, Random, Systematic Search, Simulated Annealing and Gradient methods. It exposes hybrid optimisation, Pareto fronts and repeated searches for local-minimum robustness.

References:
- https://wipl-d.com/applications/antenna-design/
- https://wipl-d.com/products/add-on-tools/optimizer/

Product lesson:
- our existing PSO/DE/Nelder-Mead + Pareto direction is sound;
- keep optimisation goals as explicit product-domain objects.

## EMMana-Next product-domain decision

Adopt:
1. Product Project
2. Design Model (.emnx)
3. Analysis Plan
4. Simulation/Optimisation execution
5. Evidence Bundle
6. Measurement Set
7. Report/Release

Do not merge these roles into one oversized JSON or one UI state object.

High-value next product features:
- antenna template/synthesis registry;
- material and ground-profile libraries with validation status;
- Touchstone/VNA import and simulation-vs-measurement comparison;
- named immutable design variants;
- report generator;
- matching-network post-processing;
- multiport/array excitation;
- queued batch studies.

Solver physics remains independently versioned and evidence-gated.
