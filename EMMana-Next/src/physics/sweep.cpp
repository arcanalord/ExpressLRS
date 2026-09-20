#include "emnext/physics/sweep.hpp"

#include "emnext/core/model_tools.hpp"
#include "emnext/core/parallel.hpp"

#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>

namespace emnext::physics {
namespace {

double dmax_dbi(const ResultSet& result) {
    double dmax = 0.0;
    for (const auto& p : result.pattern) dmax = std::max(dmax, p.directivity_linear);
    return dmax > 0.0 ? 10.0 * std::log10(dmax) : -std::numeric_limits<double>::infinity();
}

double s11_db(const Complex& s11) {
    const double mag = std::abs(s11);
    return mag > 0.0 ? 20.0 * std::log10(mag) : -300.0;
}

} // namespace

SweepResult solve_frequency_sweep(const Project& project,
                                  double start_frequency_hz,
                                  double stop_frequency_hz,
                                  int points,
                                  const WireMomSettings& settings) {
    if (!(start_frequency_hz > 0.0) || !(stop_frequency_hz > 0.0)) {
        throw std::runtime_error("Sweep frequencies must be positive");
    }
    if (stop_frequency_hz < start_frequency_hz) {
        throw std::runtime_error("Sweep stop frequency must be >= start frequency");
    }
    if (points < 2 || points > 401) {
        throw std::runtime_error("Sweep points must be in [2, 401]");
    }

    SweepResult sweep;
    sweep.source_model_hash = stable_model_hash(project);
    sweep.start_frequency_hz = start_frequency_hz;
    sweep.stop_frequency_hz = stop_frequency_hz;
    sweep.requested_points = points;
    sweep.execution_workers = configured_parallel_workers();
    std::vector<ResultSet> results(static_cast<std::size_t>(points));
    parallel_for_ordered(static_cast<std::size_t>(points), sweep.execution_workers, [&](std::size_t index) {
        const int i = static_cast<int>(index);
        const double t = static_cast<double>(i) / static_cast<double>(points - 1);
        auto p = project;
        p.frequency_hz = start_frequency_hz + t * (stop_frequency_hz - start_frequency_hz);
        results[index] = solve_wire_mom_experimental(p, settings);
    });

    sweep.samples.reserve(static_cast<std::size_t>(points));
    double best_abs_x = std::numeric_limits<double>::infinity();
    double best_s11_db = std::numeric_limits<double>::infinity();

    for (int i = 0; i < points; ++i) {
        const auto& result = results[static_cast<std::size_t>(i)];
        if (result.feeds.empty()) throw std::runtime_error("Sweep solver returned no feed result");
        const auto& feed = result.feeds.front();
        const double frequency_hz = result.frequency_hz;

        if (i == 0) {
            sweep.solver_id = result.solver_id;
            sweep.solver_version = result.solver_version;
            sweep.solver_settings_id = result.solver_settings_id;
            sweep.model_hash_algorithm = result.model_hash_algorithm;
            sweep.linear_solver_backend = result.linear_solver_backend;
        }

        SweepPoint point;
        point.frequency_hz = frequency_hz;
        point.model_hash = result.model_hash;
        point.impedance_ohm = feed.impedance_ohm;
        point.s11 = feed.s11;
        point.vswr = feed.vswr;
        point.dmax_dbi = dmax_dbi(result);
        point.efficiency = result.efficiency;
        point.power_balance_relative_error = result.power_balance_relative_error;
        point.linear_residual_relative = result.linear_residual_relative;
        sweep.max_linear_residual_relative = std::max(sweep.max_linear_residual_relative, result.linear_residual_relative);
        point.warnings = result.warnings;
        sweep.samples.push_back(std::move(point));

        const double abs_x = std::abs(feed.impedance_ohm.imag());
        if (abs_x < best_abs_x) {
            best_abs_x = abs_x;
            sweep.resonance_frequency_hz = frequency_hz;
        }
        const double db = s11_db(feed.s11);
        if (db < best_s11_db) {
            best_s11_db = db;
            sweep.min_s11_db = db;
            sweep.min_s11_frequency_hz = frequency_hz;
        }
    }

    for (std::size_t i = 1; i < sweep.samples.size(); ++i) {
        const double x0 = sweep.samples[i - 1].impedance_ohm.imag();
        const double x1 = sweep.samples[i].impedance_ohm.imag();
        if ((x0 <= 0.0 && x1 >= 0.0) || (x0 >= 0.0 && x1 <= 0.0)) {
            if (x0 == x1) {
                sweep.resonance_frequency_hz = 0.5 * (sweep.samples[i - 1].frequency_hz + sweep.samples[i].frequency_hz);
            } else {
                const double t = -x0 / (x1 - x0);
                sweep.resonance_frequency_hz = sweep.samples[i - 1].frequency_hz
                    + t * (sweep.samples[i].frequency_hz - sweep.samples[i - 1].frequency_hz);
            }
            break;
        }
    }

    if (!sweep.samples.empty()) {
        std::size_t best = 0;
        double min_db = std::numeric_limits<double>::infinity();
        for (std::size_t i = 0; i < sweep.samples.size(); ++i) {
            const double db = s11_db(sweep.samples[i].s11);
            if (db < min_db) { min_db = db; best = i; }
        }
        if (min_db <= -10.0) {
            std::size_t lo = best;
            std::size_t hi = best;
            while (lo > 0 && s11_db(sweep.samples[lo - 1].s11) <= -10.0) --lo;
            while (hi + 1 < sweep.samples.size() && s11_db(sweep.samples[hi + 1].s11) <= -10.0) ++hi;
            double f_lo = sweep.samples[lo].frequency_hz;
            double f_hi = sweep.samples[hi].frequency_hz;
            if (lo > 0) {
                const double d0 = s11_db(sweep.samples[lo - 1].s11);
                const double d1 = s11_db(sweep.samples[lo].s11);
                if (d0 != d1) {
                    const double t = (-10.0 - d0) / (d1 - d0);
                    f_lo = sweep.samples[lo - 1].frequency_hz
                        + t * (sweep.samples[lo].frequency_hz - sweep.samples[lo - 1].frequency_hz);
                }
            }
            if (hi + 1 < sweep.samples.size()) {
                const double d0 = s11_db(sweep.samples[hi].s11);
                const double d1 = s11_db(sweep.samples[hi + 1].s11);
                if (d0 != d1) {
                    const double t = (-10.0 - d0) / (d1 - d0);
                    f_hi = sweep.samples[hi].frequency_hz
                        + t * (sweep.samples[hi + 1].frequency_hz - sweep.samples[hi].frequency_hz);
                }
            }
            sweep.bandwidth_10db_hz = std::max(0.0, f_hi - f_lo);
        }
    }

    return sweep;
}

} // namespace emnext::physics
