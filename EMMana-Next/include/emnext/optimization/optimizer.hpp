#pragma once

#include "emnext/core/model.hpp"
#include "emnext/physics/wire_mom.hpp"

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace emnext::optimization {

enum class OptimizerAlgorithm { DifferentialEvolution, ParticleSwarm, StagedPsoNelderMead };
struct DesignValue { std::string id; double value{}; };
struct ConstraintViolation { std::string id; std::string kind; double amount{}; double normalized_amount{}; };
struct CandidateMetrics {
    double score{}; double vswr{}; double forward_gain_dbi{}; double front_to_back_db{}; double boom_length_m{};
    double power_balance_relative_error{}; double max_linear_residual_relative{}; double worst_vswr_frequency_hz{};
    double min_gain_frequency_hz{}; double min_front_to_back_frequency_hz{}; bool feasible{true}; int violated_constraints{};
    double total_constraint_violation{};
};
struct CandidateResult { std::string model_hash; std::vector<DesignValue> values; CandidateMetrics metrics; std::vector<ConstraintViolation> constraint_violations; };
struct ObjectiveWeights { double match{0.40}; double gain{0.30}; double front_to_back{0.20}; double size{0.10}; };
struct NamedCandidate { std::string label; CandidateResult candidate; };
struct OptimizerSettings {
    int population{10}; int generations{6}; int local_iterations{12}; std::uint64_t seed{42};
    OptimizerAlgorithm algorithm{OptimizerAlgorithm::StagedPsoNelderMead};
    double differential_weight{0.70}; double crossover_probability{0.85};
    double pso_inertia{0.72}; double pso_cognitive{1.49}; double pso_social{1.49}; double pso_velocity_fraction{0.20};
    double local_step_fraction{0.05}; ObjectiveWeights weights{}; double gain_guardrail_db{0.50}; double max_vswr{2.0}; int pareto_limit{12};
    double band_start_hz{0.0}; double band_stop_hz{0.0}; int band_points{1};
    double quantization_step_m{0.0}; double manufacturing_tolerance_m{0.0}; int robust_objective_samples{0}; int monte_carlo_samples{0};
    physics::WireKernelMode kernel_mode{physics::WireKernelMode::Reduced};
};
struct ToleranceAudit { double tolerance_m{}; int stress_cases{}; CandidateMetrics worst_case{}; bool passes_guardrails{true}; };
struct MonteCarloAudit {
    double tolerance_m{}; int samples{}; int passing_samples{}; double pass_fraction{}; double p95_vswr{}; double p05_gain_dbi{};
    double p05_front_to_back_db{}; CandidateMetrics worst_case{};
};
struct OptimizerResult {
    std::string schema_version{"0.8"}; std::string algorithm; std::string objective{"weighted-rf-v6-robust-worstcase"};
    std::string linear_solver_backend; int execution_workers{1}; std::string scheduler_mode{"flat-scenario-frequency-v1"};
    std::uint64_t seed{}; int population{}; int generations{}; int local_iterations{}; int evaluations{}; int evaluation_cache_hits{};
    CandidateResult initial; CandidateResult best; ObjectiveWeights weights{}; double gain_guardrail_db{}; double max_vswr{};
    double band_start_hz{}; double band_stop_hz{}; int band_points{1}; double quantization_step_m{}; double manufacturing_tolerance_m{};
    int robust_objective_samples{}; int monte_carlo_samples{}; std::optional<CandidateResult> initial_nominal; std::optional<CandidateResult> best_nominal;
    std::optional<ToleranceAudit> tolerance_audit; std::optional<MonteCarloAudit> monte_carlo_audit; std::optional<CandidateResult> robust_best;
    std::optional<ToleranceAudit> robust_tolerance_audit; std::vector<CandidateResult> pareto_front; std::vector<NamedCandidate> featured_candidates;
    std::vector<CandidateResult> generation_best; std::vector<CandidateResult> local_refinement_best; std::vector<std::string> warnings;
};
[[nodiscard]] const char* optimizer_algorithm_id(OptimizerAlgorithm algorithm) noexcept;
[[nodiscard]] OptimizerAlgorithm optimizer_algorithm_from_string(const std::string& value);
[[nodiscard]] double design_variable_value(const Project& project, const DesignVariable& variable);
[[nodiscard]] Project apply_design_values(const Project& project, const std::vector<double>& values);
[[nodiscard]] std::vector<ConstraintViolation> evaluate_design_constraints(const Project& project);
[[nodiscard]] OptimizerResult optimize_design(const Project& project, const OptimizerSettings& settings = {});
} // namespace emnext::optimization
