#include "emnext/core/model.hpp"
#include "emnext/core/model_tools.hpp"
#include "emnext/geometry/discretization.hpp"
#include "emnext/io/optimizer_io.hpp"
#include "emnext/io/project_io.hpp"
#include "emnext/io/result_io.hpp"
#include "emnext/io/sweep_io.hpp"
#include "emnext/linalg/linear_solver.hpp"
#include "emnext/optimization/optimizer.hpp"
#include "emnext/physics/dipole_reference.hpp"
#include "emnext/physics/sweep.hpp"
#include "emnext/physics/wire_mom.hpp"
#include "emnext/reference/nec2.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <numbers>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
void require(bool ok, const char* msg) { if (!ok) throw std::runtime_error(msg); }
std::filesystem::path bench(const char* f) { return std::filesystem::path(EMNEXT_SOURCE_DIR) / "benchmarks" / f; }
}

int main() {
    using namespace emnext;
    using namespace emnext::physics;

    DenseMatrix a(2,2); a(0,0)={3,1}; a(0,1)={1,-2}; a(1,0)={2,.5}; a(1,1)={5,1};
    const std::vector<Complex> expected{{1,-.5},{.25,2}}; std::vector<Complex> b(2);
    for (std::size_t r=0;r<2;++r) b[r]=a(r,0)*expected[0]+a(r,1)*expected[1];
    const auto linear=linalg::make_default_solver(); const auto x=linear->solve(a,b);
    require(std::abs(x[0]-expected[0])<1e-10 && std::abs(x[1]-expected[1])<1e-10,"linear solver");

    const double pi=std::numbers::pi_v<double>;
    require(std::abs(HalfWaveDipoleReference::normalized_field(pi/2)-1.0)<1e-12,"dipole reference normalization");
    require(std::abs(HalfWaveDipoleReference::normalized_field(pi/3)-HalfWaveDipoleReference::normalized_field(2*pi/3))<1e-12,"dipole reference symmetry");

    const auto b01=io::load_project(bench("B01_halfwave_dipole_51seg.emnx"));
    const auto r01=solve_wire_mom_experimental(b01);
    require(r01.schema_version=="0.6","ResultSet v0.6");
    require(r01.feeds.size()==1 && r01.segment_currents_a.size()==51,"B01 result shape");
    require(std::abs(r01.feeds[0].impedance_ohm.real()-84.7543157332)<1e-5,"B01 R regression");
    require(std::abs(r01.feeds[0].impedance_ohm.imag()-46.7280584134)<1e-5,"B01 X regression");
    require(std::abs(r01.power_balance_relative_error)<2e-3 && std::abs(r01.efficiency-1.0)<1e-12,"B01 power semantics");
    require(r01.linear_residual_relative<1e-10,"B01 residual");
    require(std::string(model_hash_algorithm_id())=="fnv1a64-emnext-model-v5","model hash v5");

    const auto b05=io::load_project(bench("B05_L_junction_topology.emnx"));
    const auto r05=solve_wire_mom_experimental(b05);
    require(r05.linear_system_size==49 && r05.junction_kcl_max_relative_error<1e-12,"B05 connected L junction");

    const auto b06=io::load_project(bench("B06_T_junction_topology.emnx"));
    const auto r06=solve_wire_mom_experimental(b06);
    require(r06.linear_system_size==74 && r06.junction_kcl_max_relative_error<1e-12,"B06 connected T junction");

    const auto b07a=io::load_project(bench("B07_continuous_straight_wire.emnx"));
    const auto b07b=io::load_project(bench("B07_split_straight_wire.emnx"));
    const auto r07a=solve_wire_mom_experimental(b07a), r07b=solve_wire_mom_experimental(b07b);
    require(std::abs(r07a.feeds[0].impedance_ohm-r07b.feeds[0].impedance_ohm)<1e-8,"B07 split invariance");

    const auto b08=io::load_project(bench("B08_copper_dipole.emnx"));
    const auto r08=solve_wire_mom_experimental(b08);
    require(r08.dissipated_power_w>0 && r08.efficiency>0.9 && r08.efficiency<1.0,"B08 conductor loss");
    require(std::abs(r08.power_balance_relative_error)<2e-3,"B08 power balance");

    const auto b09=io::load_project(bench("B09_rlc_loaded_dipole.emnx"));
    const auto r09=solve_wire_mom_experimental(b09);
    require(r09.dissipated_power_w>0 && r09.efficiency>0 && r09.efficiency<1.0,"B09 load loss");
    require(std::abs(r09.feeds[0].impedance_ohm-r01.feeds[0].impedance_ohm)>1e-3,"B09 impedance change");

    WireMomSettings exact; exact.kernel_mode=WireKernelMode::CircumferentialExactStraight;
    const auto rex=solve_wire_mom_experimental(b01,exact);
    require(rex.solver_id.find("circumferential-exact-straight")!=std::string::npos && rex.linear_residual_relative<1e-10,"exact validation kernel");

    const auto sw=solve_frequency_sweep(b01,285e6,315e6,5);
    require(sw.schema_version=="0.3" && sw.samples.size()==5 && sw.max_linear_residual_relative<1e-10,"sweep regression");
    require(sw.resonance_frequency_hz>=285e6 && sw.resonance_frequency_hz<=315e6,"sweep resonance marker");
    require(io::sweep_to_json(sw).find("source_model_hash")!=std::string::npos,"sweep serialization");

    const auto yagi=io::load_project(bench("B04_three_element_yagi.emnx"));
    const auto ry=solve_wire_mom_experimental(yagi);
    double dmax=0,plus=0,minus=0;
    for(const auto& p:ry.pattern){ dmax=std::max(dmax,p.directivity_linear); if(std::abs(p.theta_rad-pi/2)<1e-12&&std::abs(p.phi_rad)<1e-12)plus=p.directivity_linear; if(std::abs(p.theta_rad-pi/2)<1e-12&&std::abs(p.phi_rad-pi)<1e-12)minus=p.directivity_linear; }
    require(dmax>5.0 && plus>10.0*minus,"B04 directive sanity");

    const auto yp=io::load_project(bench("B04_three_element_yagi_parametric.emnx"));
    require(yp.design_variables.size()==5 && yp.design_constraints.size()==5,"B04 parametric model");
    require(optimization::evaluate_design_constraints(yp).empty(),"B04 baseline constraints");
    optimization::OptimizerSettings os; os.population=4; os.generations=1; os.local_iterations=0; os.seed=42; os.algorithm=optimization::OptimizerAlgorithm::ParticleSwarm; os.weights={50,25,15,10}; os.quantization_step_m=.001; os.manufacturing_tolerance_m=.001; os.robust_objective_samples=1; os.monte_carlo_samples=2;
    const auto opt=optimization::optimize_design(yp,os);
    require(opt.schema_version=="0.8" && opt.best.metrics.feasible && opt.best.values.size()==5,"optimizer regression");
    require(opt.best.metrics.score<=opt.initial.metrics.score+1e-12 && !opt.pareto_front.empty(),"optimizer improves/Pareto");
    require(opt.monte_carlo_audit.has_value() && opt.monte_carlo_audit->samples==2,"optimizer MC audit");

    const std::string deck=reference::export_nec2_deck(b01);
    require(deck.find("GW 1 51")!=std::string::npos && deck.find("EX 0 1 26 0")!=std::string::npos,"NEC2 export");
    const auto ce_pos=deck.find("CE\n");
    const auto wire_comment_pos=deck.find("CM WIRE 1 = W1");
    require(ce_pos!=std::string::npos && wire_comment_pos!=std::string::npos && wire_comment_pos<ce_pos,"NEC2 comments must precede CE");
    require(deck.find("CM ",ce_pos+3)==std::string::npos,"NEC2 geometry/control section must not contain CM cards");
    const std::string js=io::result_to_json(r01);
    require(js.find("ground_dissipated_power_w")!=std::string::npos && js.find("fnv1a64-emnext-model-v5")!=std::string::npos,"ResultSet provenance");

    std::cout << "PASS alpha.20 full bootstrap/core regressions using " << linear->name() << "\n";
    return 0;
}
