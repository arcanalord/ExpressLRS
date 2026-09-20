#include "emnext/optimization/optimizer.hpp"

#include "emnext/core/model_tools.hpp"
#include "emnext/core/parallel.hpp"
#include "emnext/linalg/linear_solver.hpp"

#include <algorithm>
#include <cmath>
#include <limits>
#include <numbers>
#include <random>
#include <sstream>
#include <stdexcept>
#include <unordered_map>

namespace emnext::optimization {
namespace {

Wire& wire_by_id(Project& project, const std::string& id) {
    const auto it = std::find_if(project.wires.begin(), project.wires.end(), [&](const Wire& w) { return w.id == id; });
    if (it == project.wires.end()) throw std::runtime_error("Design variable references unknown wire: " + id);
    return *it;
}

const Wire& wire_by_id(const Project& project, const std::string& id) {
    const auto it = std::find_if(project.wires.begin(), project.wires.end(), [&](const Wire& w) { return w.id == id; });
    if (it == project.wires.end()) throw std::runtime_error("Design variable references unknown wire: " + id);
    return *it;
}

Vec3 midpoint(const Wire& w) {
    return {(w.start.x + w.end.x) * 0.5, (w.start.y + w.end.y) * 0.5, (w.start.z + w.end.z) * 0.5};
}

void set_wire_length(Wire& w, double length) {
    if (!(length > 0.0)) throw std::runtime_error("Wire length design value must be positive");
    const Vec3 d{w.end.x - w.start.x, w.end.y - w.start.y, w.end.z - w.start.z};
    const double old = std::sqrt(d.x*d.x + d.y*d.y + d.z*d.z);
    if (!(old > 0.0)) throw std::runtime_error("Cannot resize zero-length wire " + w.id);
    const Vec3 u{d.x/old, d.y/old, d.z/old};
    const Vec3 m = midpoint(w);
    const double h = 0.5 * length;
    w.start = {m.x-u.x*h, m.y-u.y*h, m.z-u.z*h};
    w.end   = {m.x+u.x*h, m.y+u.y*h, m.z+u.z*h};
}

void set_wire_center_x(Wire& w, double x) {
    const Vec3 m = midpoint(w);
    const double dx = x - m.x;
    w.start.x += dx;
    w.end.x += dx;
}

double db10(double x) {
    if (!(x > 0.0)) return -300.0;
    return 10.0 * std::log10(x);
}

double pattern_at(const ResultSet& result, double theta, double phi) {
    double best_distance = std::numeric_limits<double>::infinity();
    double value = 0.0;
    for (const auto& p : result.pattern) {
        double dp = std::abs(p.phi_rad - phi);
        dp = std::min(dp, 2.0*std::numbers::pi_v<double> - dp);
        const double d = std::abs(p.theta_rad-theta) + dp;
        if (d < best_distance) { best_distance = d; value = p.gain_linear; }
    }
    return value;
}

double boom_length(const Project& project) {
    if (project.wires.empty()) return 0.0;
    double lo = std::numeric_limits<double>::infinity();
    double hi = -std::numeric_limits<double>::infinity();
    for (const auto& w : project.wires) {
        const double x = midpoint(w).x;
        lo = std::min(lo, x);
        hi = std::max(hi, x);
    }
    return hi - lo;
}

CandidateMetrics single_frequency_metrics(const Project& project, const ResultSet& result) {
    if (result.feeds.empty()) throw std::runtime_error("Optimizer evaluation returned no feed result");
    const double forward = pattern_at(result, std::numbers::pi_v<double>/2.0, 0.0);
    const double back = pattern_at(result, std::numbers::pi_v<double>/2.0, std::numbers::pi_v<double>);
    CandidateMetrics m;
    m.vswr = result.feeds.front().vswr;
    m.forward_gain_dbi = db10(std::max(forward, 1e-30));
    m.front_to_back_db = 10.0 * std::log10(std::max(forward,1e-30) / std::max(back,1e-30));
    m.boom_length_m = boom_length(project);
    m.power_balance_relative_error = std::abs(result.power_balance_relative_error);
    m.max_linear_residual_relative = result.linear_residual_relative;
    m.worst_vswr_frequency_hz = project.frequency_hz;
    m.min_gain_frequency_hz = project.frequency_hz;
    m.min_front_to_back_frequency_hz = project.frequency_hz;
    return m;
}

std::vector<double> evaluation_frequencies(const Project& project, const OptimizerSettings& settings) {
    if (settings.band_points <= 1) return {project.frequency_hz};
    std::vector<double> out;
    out.reserve(static_cast<std::size_t>(settings.band_points));
    const double step = (settings.band_stop_hz - settings.band_start_hz) / static_cast<double>(settings.band_points - 1);
    for (int i=0;i<settings.band_points;++i) out.push_back(settings.band_start_hz + step * static_cast<double>(i));
    return out;
}

CandidateMetrics raw_metrics_for(const Project& project,
                                 const OptimizerSettings& settings,
                                 const physics::WireMomSettings& solver_settings) {
    const auto frequencies = evaluation_frequencies(project, settings);
    CandidateMetrics aggregate;
    aggregate.vswr = -std::numeric_limits<double>::infinity();
    aggregate.forward_gain_dbi = std::numeric_limits<double>::infinity();
    aggregate.front_to_back_db = std::numeric_limits<double>::infinity();
    aggregate.boom_length_m = boom_length(project);
    aggregate.power_balance_relative_error = 0.0;
    aggregate.max_linear_residual_relative = 0.0;

    std::vector<CandidateMetrics> per_frequency(frequencies.size());
    const int workers = configured_parallel_workers();
    parallel_for_ordered(frequencies.size(), workers, [&](std::size_t index) {
        Project p = project;
        p.frequency_hz = frequencies[index];
        const auto result = physics::solve_wire_mom_experimental(p, solver_settings);
        per_frequency[index] = single_frequency_metrics(p, result);
    });

    for (std::size_t index = 0; index < frequencies.size(); ++index) {
        const double frequency_hz = frequencies[index];
        const auto& m = per_frequency[index];
        if (m.vswr > aggregate.vswr) {
            aggregate.vswr = m.vswr;
            aggregate.worst_vswr_frequency_hz = frequency_hz;
        }
        if (m.forward_gain_dbi < aggregate.forward_gain_dbi) {
            aggregate.forward_gain_dbi = m.forward_gain_dbi;
            aggregate.min_gain_frequency_hz = frequency_hz;
        }
        if (m.front_to_back_db < aggregate.front_to_back_db) {
            aggregate.front_to_back_db = m.front_to_back_db;
            aggregate.min_front_to_back_frequency_hz = frequency_hz;
        }
        aggregate.power_balance_relative_error = std::max(aggregate.power_balance_relative_error, m.power_balance_relative_error);
        aggregate.max_linear_residual_relative = std::max(aggregate.max_linear_residual_relative, m.max_linear_residual_relative);
    }
    return aggregate;
}

std::vector<CandidateMetrics> constrained_metrics_for_projects_flattened(
    const std::vector<Project>& physicals,
    const OptimizerSettings& settings,
    const physics::WireMomSettings& solver_settings) {
    if (physicals.empty()) return {};

    const auto frequencies = evaluation_frequencies(physicals.front(), settings);
    const std::size_t frequency_count = frequencies.size();
    const std::size_t task_count = physicals.size() * frequency_count;
    std::vector<CandidateMetrics> per_task(task_count);

    const int workers = configured_parallel_workers();
    parallel_for_ordered(task_count, workers, [&](std::size_t task_index) {
        const std::size_t physical_index = task_index / frequency_count;
        const std::size_t frequency_index = task_index % frequency_count;
        Project p = physicals[physical_index];
        p.frequency_hz = frequencies[frequency_index];
        const auto result = physics::solve_wire_mom_experimental(p, solver_settings);
        per_task[task_index] = single_frequency_metrics(p, result);
    });

    std::vector<CandidateMetrics> out(physicals.size());
    for (std::size_t physical_index = 0; physical_index < physicals.size(); ++physical_index) {
        CandidateMetrics aggregate;
        aggregate.vswr = -std::numeric_limits<double>::infinity();
        aggregate.forward_gain_dbi = std::numeric_limits<double>::infinity();
        aggregate.front_to_back_db = std::numeric_limits<double>::infinity();
        aggregate.boom_length_m = boom_length(physicals[physical_index]);
        aggregate.power_balance_relative_error = 0.0;
        aggregate.max_linear_residual_relative = 0.0;

        for (std::size_t frequency_index = 0; frequency_index < frequency_count; ++frequency_index) {
            const auto& m = per_task[physical_index * frequency_count + frequency_index];
            const double frequency_hz = frequencies[frequency_index];
            if (m.vswr > aggregate.vswr) {
                aggregate.vswr = m.vswr;
                aggregate.worst_vswr_frequency_hz = frequency_hz;
            }
            if (m.forward_gain_dbi < aggregate.forward_gain_dbi) {
                aggregate.forward_gain_dbi = m.forward_gain_dbi;
                aggregate.min_gain_frequency_hz = frequency_hz;
            }
            if (m.front_to_back_db < aggregate.front_to_back_db) {
                aggregate.front_to_back_db = m.front_to_back_db;
                aggregate.min_front_to_back_frequency_hz = frequency_hz;
            }
            aggregate.power_balance_relative_error = std::max(aggregate.power_balance_relative_error, m.power_balance_relative_error);
            aggregate.max_linear_residual_relative = std::max(aggregate.max_linear_residual_relative, m.max_linear_residual_relative);
        }

        const auto violations = evaluate_design_constraints(physicals[physical_index]);
        aggregate.feasible = violations.empty();
        aggregate.violated_constraints = static_cast<int>(violations.size());
        aggregate.total_constraint_violation = 0.0;
        for (const auto& v : violations) aggregate.total_constraint_violation += v.normalized_amount;
        out[physical_index] = aggregate;
    }
    return out;
}

ObjectiveWeights normalized_weights(const ObjectiveWeights& w) {
    if (w.match < 0.0 || w.gain < 0.0 || w.front_to_back < 0.0 || w.size < 0.0) {
        throw std::runtime_error("Optimizer objective weights must be non-negative");
    }
    const double sum = w.match + w.gain + w.front_to_back + w.size;
    if (!(sum > 0.0)) throw std::runtime_error("At least one optimizer objective weight must be positive");
    return {w.match/sum, w.gain/sum, w.front_to_back/sum, w.size/sum};
}

double normalized_objective(const CandidateMetrics& m, const CandidateMetrics& baseline, const CandidateMetrics& guardrail_baseline, const OptimizerSettings& settings) {
    const auto w = normalized_weights(settings.weights);
    const double base_match = std::max(baseline.vswr - 1.0, 0.10);
    const double match_term = std::clamp(std::max(m.vswr - 1.0, 0.0) / base_match, 0.0, 3.0);
    const double gain_term = std::clamp(std::pow(10.0, (baseline.forward_gain_dbi - m.forward_gain_dbi) / 10.0), 0.25, 3.0);
    const double fb_term = std::clamp(std::pow(10.0, (baseline.front_to_back_db - m.front_to_back_db) / 10.0), 0.25, 3.0);
    const double size_term = std::clamp(m.boom_length_m / std::max(baseline.boom_length_m, 1e-9), 0.50, 2.0);
    double score = w.match * match_term + w.gain * gain_term + w.front_to_back * fb_term + w.size * size_term;
    const double gain_floor = guardrail_baseline.forward_gain_dbi - settings.gain_guardrail_db;
    if (m.forward_gain_dbi < gain_floor) { const double deficit = gain_floor - m.forward_gain_dbi; score += 2.0 + 2.0 * deficit * deficit; }
    if (m.vswr > settings.max_vswr) { const double excess = m.vswr - settings.max_vswr; score += 2.0 + excess * excess; }
    return score;
}

std::string values_key(const std::vector<double>& values) {
    std::ostringstream os; os.setf(std::ios::scientific); os.precision(15); for (double v : values) os << v << ';'; return os.str();
}

bool better(const CandidateMetrics& a, const CandidateMetrics& b) {
    if (a.feasible != b.feasible) return a.feasible;
    if (a.violated_constraints != b.violated_constraints) return a.violated_constraints < b.violated_constraints;
    if (std::abs(a.total_constraint_violation - b.total_constraint_violation) > 1e-12) return a.total_constraint_violation < b.total_constraint_violation;
    return a.score < b.score;
}

CandidateResult to_candidate(const Project& base, const std::vector<double>& values, const CandidateMetrics& metrics) {
    CandidateResult c; c.metrics = metrics; const Project physical = apply_design_values(base, values); c.model_hash = stable_model_hash(physical);
    c.constraint_violations = evaluate_design_constraints(physical); for (std::size_t i=0;i<values.size();++i) c.values.push_back({base.design_variables[i].id, values[i]}); return c;
}

bool pareto_dominates(const CandidateMetrics& a, const CandidateMetrics& b) {
    if (!a.feasible) return false;
    if (!b.feasible) return true;
    constexpr double eps = 1e-12;
    const bool no_worse = a.vswr <= b.vswr + eps && a.forward_gain_dbi + eps >= b.forward_gain_dbi && a.front_to_back_db + eps >= b.front_to_back_db && a.boom_length_m <= b.boom_length_m + eps;
    const bool strictly_better = a.vswr < b.vswr - eps || a.forward_gain_dbi > b.forward_gain_dbi + eps || a.front_to_back_db > b.front_to_back_db + eps || a.boom_length_m < b.boom_length_m - eps;
    return no_worse && strictly_better;
}

std::vector<std::size_t> pareto_indices(const std::vector<CandidateMetrics>& metrics) {
    std::vector<std::size_t> out; for (std::size_t i=0;i<metrics.size();++i) { if (!metrics[i].feasible) continue; bool dominated=false;
        for (std::size_t j=0;j<metrics.size();++j) if (i!=j && pareto_dominates(metrics[j], metrics[i])) { dominated=true; break; }
        if (!dominated) out.push_back(i); } return out;
}

std::vector<double> canonical_values(const Project& project, const OptimizerSettings& settings, std::vector<double> values) {
    for (std::size_t j=0;j<values.size();++j) { const auto& var = project.design_variables[j]; values[j] = std::clamp(values[j], var.min_value, var.max_value);
        if (settings.quantization_step_m > 0.0) { values[j] = std::round(values[j] / settings.quantization_step_m) * settings.quantization_step_m; values[j] = std::clamp(values[j], var.min_value, var.max_value); } }
    return values;
}

void merge_worst_metrics(CandidateMetrics& worst, const CandidateMetrics& m) {
    if (m.vswr > worst.vswr) { worst.vswr = m.vswr; worst.worst_vswr_frequency_hz = m.worst_vswr_frequency_hz; }
    if (m.forward_gain_dbi < worst.forward_gain_dbi) { worst.forward_gain_dbi = m.forward_gain_dbi; worst.min_gain_frequency_hz = m.min_gain_frequency_hz; }
    if (m.front_to_back_db < worst.front_to_back_db) { worst.front_to_back_db = m.front_to_back_db; worst.min_front_to_back_frequency_hz = m.min_front_to_back_frequency_hz; }
    worst.boom_length_m = std::max(worst.boom_length_m, m.boom_length_m); worst.power_balance_relative_error = std::max(worst.power_balance_relative_error, m.power_balance_relative_error);
    worst.max_linear_residual_relative = std::max(worst.max_linear_residual_relative, m.max_linear_residual_relative);
    if (!m.feasible) { worst.feasible = false; worst.violated_constraints = std::max(worst.violated_constraints, m.violated_constraints); worst.total_constraint_violation = std::max(worst.total_constraint_violation, m.total_constraint_violation); }
}

CandidateMetrics constrained_raw_metrics_for(const Project& physical, const OptimizerSettings& settings, const physics::WireMomSettings& solver_settings) {
    auto m = raw_metrics_for(physical, settings, solver_settings); const auto violations = evaluate_design_constraints(physical); m.feasible = violations.empty();
    m.violated_constraints = static_cast<int>(violations.size()); m.total_constraint_violation = 0.0; for (const auto& v : violations) m.total_constraint_violation += v.normalized_amount; return m;
}

std::vector<std::vector<double>> robust_patterns(int samples, std::size_t dimensions, std::uint64_t seed) {
    std::vector<std::vector<double>> out; if (samples <= 0 || dimensions == 0) return out; out.reserve(static_cast<std::size_t>(samples));
    auto push_pattern = [&](std::vector<double> v) { if (static_cast<int>(out.size()) < samples) out.push_back(std::move(v)); };
    push_pattern(std::vector<double>(dimensions, 1.0)); push_pattern(std::vector<double>(dimensions, -1.0)); std::vector<double> alt(dimensions, 1.0);
    for (std::size_t j=0;j<dimensions;++j) alt[j] = (j % 2 == 0) ? 1.0 : -1.0;
    push_pattern(alt);
    for (double& x : alt) x = -x;
    push_pattern(alt);
    std::mt19937_64 rng(seed ^ 0xA13B5C7D91E2F403ULL); std::uniform_real_distribution<double> dist(-1.0, 1.0);
    while (static_cast<int>(out.size()) < samples) { std::vector<double> v(dimensions); for (double& x : v) x = dist(rng); out.push_back(std::move(v)); } return out;
}

std::vector<double> perturb_values(const Project& project, const std::vector<double>& nominal, const std::vector<double>& normalized_offsets, double tolerance_m) {
    auto out = nominal; for (std::size_t j=0;j<out.size();++j) { const auto& var = project.design_variables[j]; out[j] = std::clamp(out[j] + normalized_offsets[j] * tolerance_m, var.min_value, var.max_value); } return out;
}

CandidateMetrics embedded_robust_metrics_for(const Project& project, const std::vector<double>& nominal_values, const OptimizerSettings& settings,
                                             const physics::WireMomSettings& solver_settings, const std::vector<std::vector<double>>& patterns) {
    CandidateMetrics worst; worst.vswr = -std::numeric_limits<double>::infinity(); worst.forward_gain_dbi = std::numeric_limits<double>::infinity(); worst.front_to_back_db = std::numeric_limits<double>::infinity();
    worst.boom_length_m = 0.0; worst.power_balance_relative_error = 0.0; worst.feasible = true; std::vector<Project> physicals; physicals.reserve(patterns.size() + 1);
    physicals.push_back(apply_design_values(project, nominal_values)); for (const auto& pattern : patterns) physicals.push_back(apply_design_values(project, perturb_values(project, nominal_values, pattern, settings.manufacturing_tolerance_m)));
    for (const auto& m : constrained_metrics_for_projects_flattened(physicals, settings, solver_settings)) {
        merge_worst_metrics(worst, m);
    }
    return worst;
}

double quantile_sorted(const std::vector<double>& sorted, double q) {
    if (sorted.empty()) return 0.0;
    const double pos = std::clamp(q, 0.0, 1.0) * static_cast<double>(sorted.size() - 1);
    const auto lo = static_cast<std::size_t>(std::floor(pos));
    const auto hi = static_cast<std::size_t>(std::ceil(pos));
    if (lo == hi) return sorted[lo];
    const double t = pos - static_cast<double>(lo);
    return sorted[lo] * (1.0 - t) + sorted[hi] * t;
}

MonteCarloAudit monte_carlo_audit_for(const Project& project, const std::vector<double>& nominal_values, const CandidateMetrics& guardrail_baseline,
                                      const OptimizerSettings& settings, const physics::WireMomSettings& solver_settings) {
    MonteCarloAudit audit; audit.tolerance_m = settings.manufacturing_tolerance_m; audit.samples = settings.monte_carlo_samples; if (audit.samples <= 0) return audit;
    CandidateMetrics worst; worst.vswr = -std::numeric_limits<double>::infinity(); worst.forward_gain_dbi = std::numeric_limits<double>::infinity(); worst.front_to_back_db = std::numeric_limits<double>::infinity();
    worst.boom_length_m = 0.0; worst.power_balance_relative_error = 0.0; worst.feasible = true; std::vector<double> vswr_values, gain_values, fb_values;
    vswr_values.reserve(static_cast<std::size_t>(audit.samples)); gain_values.reserve(static_cast<std::size_t>(audit.samples)); fb_values.reserve(static_cast<std::size_t>(audit.samples));
    std::mt19937_64 rng(settings.seed ^ 0x13C0FFEE57A91D2BULL); std::uniform_real_distribution<double> dist(-1.0, 1.0); const double gain_floor = guardrail_baseline.forward_gain_dbi - settings.gain_guardrail_db;
    std::vector<Project> physicals; physicals.reserve(static_cast<std::size_t>(audit.samples)); for (int i=0;i<audit.samples;++i) { std::vector<double> pattern(nominal_values.size()); for (double& x : pattern) x = dist(rng); const auto values = perturb_values(project, nominal_values, pattern, settings.manufacturing_tolerance_m); physicals.push_back(apply_design_values(project, values)); }
    const auto metrics = constrained_metrics_for_projects_flattened(physicals, settings, solver_settings); for (const auto& m : metrics) { merge_worst_metrics(worst, m); vswr_values.push_back(m.vswr); gain_values.push_back(m.forward_gain_dbi); fb_values.push_back(m.front_to_back_db); if (m.feasible && m.vswr <= settings.max_vswr + 1e-12 && m.forward_gain_dbi >= gain_floor - 1e-12) ++audit.passing_samples; }
    std::sort(vswr_values.begin(), vswr_values.end()); std::sort(gain_values.begin(), gain_values.end()); std::sort(fb_values.begin(), fb_values.end());
    audit.pass_fraction = static_cast<double>(audit.passing_samples) / static_cast<double>(audit.samples); audit.p95_vswr = quantile_sorted(vswr_values, 0.95); audit.p05_gain_dbi = quantile_sorted(gain_values, 0.05); audit.p05_front_to_back_db = quantile_sorted(fb_values, 0.05); audit.worst_case = worst; return audit;
}

ToleranceAudit tolerance_audit_for(const Project& project, const std::vector<double>& nominal_values, const CandidateMetrics& baseline,
                                  const OptimizerSettings& settings, const physics::WireMomSettings& solver_settings) {
    ToleranceAudit audit; audit.tolerance_m = settings.manufacturing_tolerance_m; CandidateMetrics worst; worst.vswr = -std::numeric_limits<double>::infinity(); worst.forward_gain_dbi = std::numeric_limits<double>::infinity();
    worst.front_to_back_db = std::numeric_limits<double>::infinity(); worst.boom_length_m = 0.0; worst.power_balance_relative_error = 0.0; worst.feasible = true;
    std::unordered_map<std::string, bool> seen; std::vector<std::vector<double>> unique_values; auto include_case = [&](const std::vector<double>& values) { const std::string key = values_key(values); if (seen.contains(key)) return; seen.emplace(key, true); unique_values.push_back(values); };
    include_case(nominal_values); if (settings.manufacturing_tolerance_m > 0.0) { for (std::size_t j=0;j<nominal_values.size();++j) { for (double sign : {-1.0, 1.0}) { auto v = nominal_values; const auto& var = project.design_variables[j]; v[j] = std::clamp(v[j] + sign * settings.manufacturing_tolerance_m, var.min_value, var.max_value); include_case(v); } } }
    std::vector<Project> physicals; physicals.reserve(unique_values.size()); for (const auto& values : unique_values) physicals.push_back(apply_design_values(project, values));
    for (const auto& m : constrained_metrics_for_projects_flattened(physicals, settings, solver_settings)) { merge_worst_metrics(worst, m); ++audit.stress_cases; }
    audit.worst_case = worst; const double gain_floor = baseline.forward_gain_dbi - settings.gain_guardrail_db; audit.passes_guardrails = worst.feasible && worst.vswr <= settings.max_vswr + 1e-12 && worst.forward_gain_dbi >= gain_floor - 1e-12; return audit;
}

} // namespace

const char* optimizer_algorithm_id(OptimizerAlgorithm algorithm) noexcept {
    switch (algorithm) { case OptimizerAlgorithm::DifferentialEvolution: return "differential-evolution-rand1-bin"; case OptimizerAlgorithm::ParticleSwarm: return "particle-swarm"; case OptimizerAlgorithm::StagedPsoNelderMead: return "particle-swarm+nelder-mead"; }
    return "unknown";
}

OptimizerAlgorithm optimizer_algorithm_from_string(const std::string& value) {
    if (value == "de" || value == "differential-evolution-rand1-bin") return OptimizerAlgorithm::DifferentialEvolution;
    if (value == "pso" || value == "particle-swarm") return OptimizerAlgorithm::ParticleSwarm;
    if (value == "staged" || value == "particle-swarm+nelder-mead") return OptimizerAlgorithm::StagedPsoNelderMead;
    throw std::runtime_error("optimizer algorithm must be de, pso, or staged");
}

double design_variable_value(const Project& project, const DesignVariable& variable) {
    const auto& w = wire_by_id(project, variable.wire_id); if (variable.kind == "wire_length_m") return wire_length_m(w); if (variable.kind == "wire_center_x_m") return midpoint(w).x; throw std::runtime_error("Unsupported design variable kind: " + variable.kind);
}

Project apply_design_values(const Project& project, const std::vector<double>& values) {
    if (values.size() != project.design_variables.size()) throw std::runtime_error("Design value count mismatch");
    Project out = project;
    for (std::size_t i=0;i<values.size();++i) {
        const auto& var = project.design_variables[i]; const double value = values[i]; if (value < var.min_value || value > var.max_value) throw std::runtime_error("Design value outside bounds: " + var.id);
        auto& w = wire_by_id(out, var.wire_id); if (var.kind == "wire_length_m") set_wire_length(w, value); else if (var.kind == "wire_center_x_m") set_wire_center_x(w, value); else throw std::runtime_error("Unsupported design variable kind: " + var.kind);
    }
    const auto check = check_model(out); if (!check.ok()) throw std::runtime_error("Parameterized project failed model-check"); return out;
}

std::vector<ConstraintViolation> evaluate_design_constraints(const Project& project) {
    std::vector<ConstraintViolation> out; for (const auto& c : project.design_constraints) { double amount = 0.0; double scale = std::max(c.value, 0.01);
        if (c.kind == "min_center_x_gap_m") { const double xa = midpoint(wire_by_id(project, c.wire_a)).x; const double xb = midpoint(wire_by_id(project, c.wire_b)).x; amount = std::max(0.0, c.value - (xb - xa)); }
        else if (c.kind == "wire_length_order_min_delta_m") { const double la = wire_length_m(wire_by_id(project, c.wire_a)); const double lb = wire_length_m(wire_by_id(project, c.wire_b)); amount = std::max(0.0, c.value - (la - lb)); }
        else if (c.kind == "max_boom_length_m") { amount = std::max(0.0, boom_length(project) - c.value); scale = std::max(c.value, 0.01); }
        else throw std::runtime_error("Unsupported design constraint kind: " + c.kind);
        if (amount > 1e-12) out.push_back({c.id, c.kind, amount, amount/scale});
    } return out;
}

OptimizerResult optimize_design(const Project& project, const OptimizerSettings& settings) {
    if (project.design_variables.empty()) throw std::runtime_error("Project has no design_variables");
    if (project.design_variables.size() > 12) throw std::runtime_error("Alpha optimizer supports at most 12 design variables");
    if (settings.population < 4 || settings.population > 64) throw std::runtime_error("Optimizer population must be in [4,64]");
    if (settings.generations < 1 || settings.generations > 100) throw std::runtime_error("Optimizer generations must be in [1,100]");
    if (settings.local_iterations < 0 || settings.local_iterations > 100) throw std::runtime_error("Optimizer local_iterations must be in [0,100]");
    if (!(settings.differential_weight > 0.0 && settings.differential_weight <= 2.0)) throw std::runtime_error("Invalid differential weight");
    if (!(settings.crossover_probability > 0.0 && settings.crossover_probability <= 1.0)) throw std::runtime_error("Invalid crossover probability");
    if (!(settings.pso_inertia >= 0.0 && settings.pso_inertia <= 1.2)) throw std::runtime_error("Invalid PSO inertia");
    if (!(settings.pso_cognitive >= 0.0 && settings.pso_cognitive <= 4.0)) throw std::runtime_error("Invalid PSO cognitive coefficient");
    if (!(settings.pso_social >= 0.0 && settings.pso_social <= 4.0)) throw std::runtime_error("Invalid PSO social coefficient");
    if (!(settings.pso_velocity_fraction > 0.0 && settings.pso_velocity_fraction <= 1.0)) throw std::runtime_error("Invalid PSO velocity fraction");
    if (!(settings.local_step_fraction > 0.0 && settings.local_step_fraction <= 0.5)) throw std::runtime_error("Invalid local step fraction");
    (void)normalized_weights(settings.weights); if (!(settings.gain_guardrail_db >= 0.0 && settings.gain_guardrail_db <= 20.0)) throw std::runtime_error("gain_guardrail_db must be in [0,20]");
    if (!(settings.max_vswr >= 1.0 && settings.max_vswr <= 100.0)) throw std::runtime_error("max_vswr must be in [1,100]");
    if (settings.pareto_limit < 1 || settings.pareto_limit > 64) throw std::runtime_error("pareto_limit must be in [1,64]");
    if (settings.band_points < 1 || settings.band_points > 11) throw std::runtime_error("band_points must be in [1,11]");
    if (settings.band_points > 1 && !(settings.band_start_hz > 0.0 && settings.band_stop_hz > settings.band_start_hz)) throw std::runtime_error("Band mode requires 0 < band_start_hz < band_stop_hz");
    if (!(settings.quantization_step_m >= 0.0 && settings.quantization_step_m <= 0.05)) throw std::runtime_error("quantization_step_m must be in [0,0.05]");
    if (!(settings.manufacturing_tolerance_m >= 0.0 && settings.manufacturing_tolerance_m <= 0.02)) throw std::runtime_error("manufacturing_tolerance_m must be in [0,0.02]");
    if (settings.robust_objective_samples < 0 || settings.robust_objective_samples > 32) throw std::runtime_error("robust_objective_samples must be in [0,32]");
    if (settings.monte_carlo_samples < 0 || settings.monte_carlo_samples > 512) throw std::runtime_error("monte_carlo_samples must be in [0,512]");
    if ((settings.robust_objective_samples > 0 || settings.monte_carlo_samples > 0) && !(settings.manufacturing_tolerance_m > 0.0)) throw std::runtime_error("robust/Monte-Carlo sampling requires manufacturing_tolerance_m > 0");

    const std::size_t n = project.design_variables.size(); std::mt19937_64 rng(settings.seed); std::uniform_real_distribution<double> unit(0.0, 1.0);
    std::vector<double> initial(n); for (std::size_t j=0;j<n;++j) { const auto& var = project.design_variables[j]; initial[j] = std::clamp(design_variable_value(project,var), var.min_value, var.max_value); } initial = canonical_values(project, settings, std::move(initial));
    int evaluations=0, cache_hits=0; std::unordered_map<std::string,CandidateMetrics> cache; std::unordered_map<std::string,std::vector<double>> evaluated_values; physics::WireMomSettings solver_settings; solver_settings.kernel_mode=settings.kernel_mode;
    Project initial_project=apply_design_values(project,initial); CandidateMetrics initial_nominal_metrics=constrained_raw_metrics_for(initial_project,settings,solver_settings); auto patterns = robust_patterns(settings.robust_objective_samples, n, settings.seed);
    const bool robust_mode = settings.robust_objective_samples > 0 && settings.manufacturing_tolerance_m > 0.0; CandidateMetrics initial_metrics = robust_mode ? embedded_robust_metrics_for(project, initial, settings, solver_settings, patterns) : initial_nominal_metrics;
    initial_metrics.score=1.0; if (!initial_metrics.feasible) initial_metrics.score += 10.0 + 25.0 * initial_metrics.total_constraint_violation + 2.0 * static_cast<double>(initial_metrics.violated_constraints);
    cache.emplace(values_key(initial),initial_metrics); evaluated_values.emplace(values_key(initial), initial); ++evaluations;
    auto evaluate = [&](const std::vector<double>& values) { const std::string key=values_key(values); if (auto it=cache.find(key); it!=cache.end()) { ++cache_hits; return it->second; }
        Project candidate=apply_design_values(project,values); auto m = robust_mode ? embedded_robust_metrics_for(project, values, settings, solver_settings, patterns) : constrained_raw_metrics_for(candidate, settings, solver_settings);
        m.score=normalized_objective(m,initial_metrics,initial_nominal_metrics,settings); if (!m.feasible) m.score += 10.0 + 25.0 * m.total_constraint_violation + 2.0 * static_cast<double>(m.violated_constraints);
        cache.emplace(key,m); evaluated_values.emplace(key, values); ++evaluations; return m; };

    OptimizerResult out; out.linear_solver_backend = std::string(linalg::make_default_solver()->name()); out.execution_workers = configured_parallel_workers(); out.scheduler_mode = "flat-scenario-frequency-v1";
    out.algorithm=optimizer_algorithm_id(settings.algorithm); out.objective = robust_mode ? "weighted-rf-v6-embedded-tolerance-worstcase" : "weighted-rf-v5-band-worstcase"; out.seed=settings.seed; out.population=settings.population;
    out.generations=settings.generations; out.local_iterations=(settings.algorithm == OptimizerAlgorithm::StagedPsoNelderMead) ? settings.local_iterations : 0; out.weights=normalized_weights(settings.weights);
    out.gain_guardrail_db=settings.gain_guardrail_db; out.max_vswr=settings.max_vswr; out.band_start_hz=settings.band_points > 1 ? settings.band_start_hz : project.frequency_hz; out.band_stop_hz=settings.band_points > 1 ? settings.band_stop_hz : project.frequency_hz;
    out.band_points=settings.band_points; out.quantization_step_m=settings.quantization_step_m; out.manufacturing_tolerance_m=settings.manufacturing_tolerance_m; out.robust_objective_samples=settings.robust_objective_samples; out.monte_carlo_samples=settings.monte_carlo_samples;
    out.initial=to_candidate(project,initial,initial_metrics); initial_nominal_metrics.score = normalized_objective(initial_nominal_metrics, initial_nominal_metrics, initial_nominal_metrics, settings); out.initial_nominal = to_candidate(project, initial, initial_nominal_metrics);

    std::vector<double> global_best_values=initial; CandidateMetrics global_best_metrics=initial_metrics;
    if (settings.algorithm == OptimizerAlgorithm::DifferentialEvolution) {
        std::uniform_int_distribution<int> pick(0, settings.population-1); std::vector<std::vector<double>> pop(static_cast<std::size_t>(settings.population), std::vector<double>(n)); std::vector<CandidateMetrics> metrics(static_cast<std::size_t>(settings.population));
        pop[0]=initial; metrics[0]=initial_metrics; for (int i=1;i<settings.population;++i) { for (std::size_t j=0;j<n;++j) { const auto& var=project.design_variables[j]; pop[static_cast<std::size_t>(i)][j]=var.min_value+unit(rng)*(var.max_value-var.min_value); }
            pop[static_cast<std::size_t>(i)] = canonical_values(project, settings, std::move(pop[static_cast<std::size_t>(i)])); metrics[static_cast<std::size_t>(i)]=evaluate(pop[static_cast<std::size_t>(i)]); }
        auto best_index=[&](){ std::size_t b=0; for(std::size_t i=1;i<metrics.size();++i) if(better(metrics[i],metrics[b])) b=i; return b; };
        for(int gen=0;gen<settings.generations;++gen){ for(int i=0;i<settings.population;++i){ int a,b,c; do{a=pick(rng);}while(a==i); do{b=pick(rng);}while(b==i||b==a); do{c=pick(rng);}while(c==i||c==a||c==b);
                auto trial=pop[static_cast<std::size_t>(i)]; std::uniform_int_distribution<int> forced(0,static_cast<int>(n)-1); const int forced_j=forced(rng);
                for(std::size_t j=0;j<n;++j){ if(unit(rng)<=settings.crossover_probability||static_cast<int>(j)==forced_j){ const auto& var=project.design_variables[j]; const double mutant=pop[static_cast<std::size_t>(a)][j]+settings.differential_weight*(pop[static_cast<std::size_t>(b)][j]-pop[static_cast<std::size_t>(c)][j]); trial[j]=std::clamp(mutant,var.min_value,var.max_value); } }
                trial = canonical_values(project, settings, std::move(trial)); const auto tm=evaluate(trial); if(better(tm,metrics[static_cast<std::size_t>(i)])){ pop[static_cast<std::size_t>(i)]=std::move(trial); metrics[static_cast<std::size_t>(i)]=tm; } }
            const auto bi=best_index(); out.generation_best.push_back(to_candidate(project,pop[bi],metrics[bi])); }
        const auto bi=best_index(); global_best_values=pop[bi]; global_best_metrics=metrics[bi];
    } else {
        std::vector<std::vector<double>> pos(static_cast<std::size_t>(settings.population), std::vector<double>(n)); std::vector<std::vector<double>> vel(static_cast<std::size_t>(settings.population), std::vector<double>(n,0.0));
        std::vector<std::vector<double>> pbest=pos; std::vector<CandidateMetrics> current(static_cast<std::size_t>(settings.population)); std::vector<CandidateMetrics> pbest_metrics(static_cast<std::size_t>(settings.population));
        pos[0]=initial; current[0]=initial_metrics; for(int i=1;i<settings.population;++i){ for(std::size_t j=0;j<n;++j){ const auto& var=project.design_variables[j]; const double range=var.max_value-var.min_value; pos[static_cast<std::size_t>(i)][j]=var.min_value+unit(rng)*range; vel[static_cast<std::size_t>(i)][j]=(2.0*unit(rng)-1.0)*settings.pso_velocity_fraction*range; }
            pos[static_cast<std::size_t>(i)] = canonical_values(project, settings, std::move(pos[static_cast<std::size_t>(i)])); current[static_cast<std::size_t>(i)]=evaluate(pos[static_cast<std::size_t>(i)]); }
        pbest=pos; pbest_metrics=current; auto refresh_global=[&](){ std::size_t bi=0; for(std::size_t i=1;i<pbest_metrics.size();++i) if(better(pbest_metrics[i],pbest_metrics[bi])) bi=i; global_best_values=pbest[bi]; global_best_metrics=pbest_metrics[bi]; };
        refresh_global(); for(int gen=0;gen<settings.generations;++gen){ for(int i=0;i<settings.population;++i){ for(std::size_t j=0;j<n;++j){ const auto& var=project.design_variables[j]; const double range=var.max_value-var.min_value; const double vmax=settings.pso_velocity_fraction*range; const double r1=unit(rng),r2=unit(rng);
                    double v=settings.pso_inertia*vel[static_cast<std::size_t>(i)][j] + settings.pso_cognitive*r1*(pbest[static_cast<std::size_t>(i)][j]-pos[static_cast<std::size_t>(i)][j]) + settings.pso_social*r2*(global_best_values[j]-pos[static_cast<std::size_t>(i)][j]);
                    v=std::clamp(v,-vmax,vmax); vel[static_cast<std::size_t>(i)][j]=v; pos[static_cast<std::size_t>(i)][j]=std::clamp(pos[static_cast<std::size_t>(i)][j]+v,var.min_value,var.max_value); }
                pos[static_cast<std::size_t>(i)] = canonical_values(project, settings, std::move(pos[static_cast<std::size_t>(i)])); current[static_cast<std::size_t>(i)]=evaluate(pos[static_cast<std::size_t>(i)]); if(better(current[static_cast<std::size_t>(i)],pbest_metrics[static_cast<std::size_t>(i)])){ pbest[static_cast<std::size_t>(i)]=pos[static_cast<std::size_t>(i)]; pbest_metrics[static_cast<std::size_t>(i)]=current[static_cast<std::size_t>(i)]; } }
            refresh_global(); out.generation_best.push_back(to_candidate(project,global_best_values,global_best_metrics)); }
    }

    if (settings.algorithm == OptimizerAlgorithm::StagedPsoNelderMead && settings.local_iterations > 0) {
        struct Vertex { std::vector<double> x; CandidateMetrics m; }; std::vector<Vertex> simplex; simplex.push_back({global_best_values,global_best_metrics});
        for(std::size_t j=0;j<n;++j){ auto x=global_best_values; const auto& var=project.design_variables[j]; const double step=settings.local_step_fraction*(var.max_value-var.min_value); double candidate=x[j]+step; if(candidate>var.max_value) candidate=x[j]-step; x[j]=std::clamp(candidate,var.min_value,var.max_value); x=canonical_values(project, settings, std::move(x)); simplex.push_back({x,evaluate(x)}); }
        const auto sort_simplex=[&](){ std::sort(simplex.begin(),simplex.end(),[](const Vertex& a,const Vertex& b){return better(a.m,b.m);}); }; sort_simplex();
        for(int iter=0;iter<settings.local_iterations;++iter){ sort_simplex(); std::vector<double> centroid(n,0.0); for(std::size_t i=0;i<n;++i) for(std::size_t j=0;j<n;++j) centroid[j]+=simplex[i].x[j]/static_cast<double>(n); const auto& worst=simplex[n];
            auto affine=[&](double factor){ std::vector<double> x(n); for(std::size_t j=0;j<n;++j) x[j]=centroid[j]+factor*(centroid[j]-worst.x[j]); return canonical_values(project,settings,std::move(x)); };
            auto xr=affine(1.0); CandidateMetrics mr=evaluate(xr); if(better(mr,simplex[0].m)){ auto xe=affine(2.0); CandidateMetrics me=evaluate(xe); simplex[n]=better(me,mr)?Vertex{xe,me}:Vertex{xr,mr}; }
            else if(better(mr,simplex[n-1].m)) simplex[n]={xr,mr}; else { std::vector<double> xc(n); const bool outside=better(mr,worst.m); for(std::size_t j=0;j<n;++j) xc[j]=outside ? centroid[j]+0.5*(xr[j]-centroid[j]) : centroid[j]+0.5*(worst.x[j]-centroid[j]); xc=canonical_values(project,settings,std::move(xc)); CandidateMetrics mc=evaluate(xc);
                if(better(mc, outside?mr:worst.m)) simplex[n]={xc,mc}; else { const auto best_x=simplex[0].x; for(std::size_t i=1;i<simplex.size();++i){ for(std::size_t j=0;j<n;++j) simplex[i].x[j]=best_x[j]+0.5*(simplex[i].x[j]-best_x[j]); simplex[i].x=canonical_values(project,settings,std::move(simplex[i].x)); simplex[i].m=evaluate(simplex[i].x); } } }
            sort_simplex(); out.local_refinement_best.push_back(to_candidate(project,simplex[0].x,simplex[0].m)); }
        sort_simplex(); if(better(simplex[0].m,global_best_metrics)){ global_best_values=simplex[0].x; global_best_metrics=simplex[0].m; }
    }

    out.best=to_candidate(project,global_best_values,global_best_metrics);
    { const Project best_physical = apply_design_values(project, global_best_values); auto best_nominal_metrics = constrained_raw_metrics_for(best_physical, settings, solver_settings); best_nominal_metrics.score = normalized_objective(best_nominal_metrics, initial_nominal_metrics, initial_nominal_metrics, settings); if (!best_nominal_metrics.feasible) best_nominal_metrics.score += 10.0 + 25.0 * best_nominal_metrics.total_constraint_violation + 2.0 * static_cast<double>(best_nominal_metrics.violated_constraints); out.best_nominal = to_candidate(project, global_best_values, best_nominal_metrics); }
    if (settings.manufacturing_tolerance_m > 0.0) {
        out.tolerance_audit = tolerance_audit_for(project, global_best_values, initial_nominal_metrics, settings, solver_settings);
    }
    out.evaluations=evaluations;
    out.evaluation_cache_hits=cache_hits;
    std::vector<std::vector<double>> archive_values; std::vector<CandidateMetrics> archive_metrics; archive_values.reserve(evaluated_values.size()); archive_metrics.reserve(evaluated_values.size());
    for (const auto& [key, values] : evaluated_values) { const auto it=cache.find(key); if (it == cache.end()) continue; if (!it->second.feasible) continue; if (it->second.forward_gain_dbi < initial_nominal_metrics.forward_gain_dbi - settings.gain_guardrail_db - 1e-12) continue; if (it->second.vswr > settings.max_vswr + 1e-12) continue; archive_values.push_back(values); archive_metrics.push_back(it->second); }
    auto pidx=pareto_indices(archive_metrics); std::sort(pidx.begin(),pidx.end(),[&](std::size_t a,std::size_t b){ return archive_metrics[a].score < archive_metrics[b].score; }); std::vector<CandidateResult> full_pareto; full_pareto.reserve(pidx.size()); for (const auto i : pidx) full_pareto.push_back(to_candidate(project,archive_values[i],archive_metrics[i]));
    const std::size_t shown = std::min(full_pareto.size(), static_cast<std::size_t>(settings.pareto_limit)); out.pareto_front.assign(full_pareto.begin(), full_pareto.begin() + static_cast<std::ptrdiff_t>(shown));
    const auto add_featured=[&](const std::string& label, auto pred){ if (full_pareto.empty()) return; auto it=std::min_element(full_pareto.begin(),full_pareto.end(),pred); if (it == full_pareto.end()) return; const bool exists=std::any_of(out.featured_candidates.begin(),out.featured_candidates.end(),[&](const NamedCandidate& named){ return named.candidate.model_hash==it->model_hash; }); if (!exists) out.featured_candidates.push_back({label,*it}); };
    add_featured("balanced",[](const CandidateResult& a,const CandidateResult& b){return a.metrics.score<b.metrics.score;}); add_featured("best-match",[](const CandidateResult& a,const CandidateResult& b){return a.metrics.vswr<b.metrics.vswr;}); add_featured("max-gain",[](const CandidateResult& a,const CandidateResult& b){return a.metrics.forward_gain_dbi>b.metrics.forward_gain_dbi;}); add_featured("max-front-to-back",[](const CandidateResult& a,const CandidateResult& b){return a.metrics.front_to_back_db>b.metrics.front_to_back_db;}); add_featured("compact",[](const CandidateResult& a,const CandidateResult& b){return a.metrics.boom_length_m<b.metrics.boom_length_m;});
    if (settings.manufacturing_tolerance_m > 0.0) { const std::size_t audit_limit = std::min<std::size_t>(full_pareto.size(), 8); for (std::size_t i=0;i<audit_limit;++i) { std::vector<double> values; values.reserve(full_pareto[i].values.size()); for (const auto& v : full_pareto[i].values) values.push_back(v.value); const auto audit = tolerance_audit_for(project, values, initial_nominal_metrics, settings, solver_settings); if (audit.passes_guardrails) { out.robust_best = full_pareto[i]; out.robust_tolerance_audit = audit; if (full_pareto[i].model_hash != out.best.model_hash) out.featured_candidates.insert(out.featured_candidates.begin(), NamedCandidate{"robust-balanced", full_pareto[i]}); break; } } }
    if (settings.monte_carlo_samples > 0 && settings.manufacturing_tolerance_m > 0.0) { std::vector<double> selected_values = global_best_values; if (out.robust_best) { selected_values.clear(); for (const auto& v : out.robust_best->values) selected_values.push_back(v.value); } out.monte_carlo_audit = monte_carlo_audit_for(project, selected_values, initial_nominal_metrics, settings, solver_settings); }
    out.warnings.push_back("Alpha.16 uses one bounded flat scheduler over independent scenario x frequency solves; nested worker pools are not used"); out.warnings.push_back("Band mode uses worst-case VSWR and minimum gain/F-B across the requested frequency samples"); if (robust_mode) out.warnings.push_back("Robust objective embeds the same fixed tolerance perturbation set into every candidate evaluation; this is deterministic for a given seed"); out.warnings.push_back("Manufacturing quantization is applied during search; axis tolerance audit and Monte-Carlo audit are independent post-search checks"); out.warnings.push_back("Embedded robust sampling is approximate, not an exhaustive 2^N tolerance-corner proof"); out.warnings.push_back("Pareto candidates are filtered by design constraints, gain guardrail and max VSWR before presentation"); out.warnings.push_back("Global stochastic optimizers are seed-dependent; always verify selected geometry with a denser sweep and an independent reference solver");
    return out;
}

} // namespace emnext::optimization
