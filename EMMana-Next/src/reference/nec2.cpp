#include "emnext/reference/nec2.hpp"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_map>

namespace emnext::reference {
namespace {

std::string trim(std::string s) {
    const auto not_space = [](unsigned char c) { return !std::isspace(c); };
    s.erase(s.begin(), std::find_if(s.begin(), s.end(), not_space));
    s.erase(std::find_if(s.rbegin(), s.rend(), not_space).base(), s.end());
    return s;
}

double parse_num(const std::string& s) { return std::stod(s); }

} // namespace

std::string export_nec2_deck(const Project& project) {
    if (project.wires.empty()) throw std::runtime_error("Cannot export NEC2 deck without wires");
    if (std::any_of(project.wires.begin(), project.wires.end(), [](const Wire& w) { return w.conductivity_s_per_m > 0.0; })) {
        throw std::runtime_error("NEC2 export of finite-conductivity wires is not implemented/validated yet; refusing to drop conductor losses");
    }
    if (!project.loads.empty()) {
        throw std::runtime_error("NEC2 export of series R/L/C loads is not implemented/validated yet; refusing to drop loads");
    }
    if (project.ground.model != "free-space" && std::abs(project.ground.plane_z_m) > 1e-12) {
        throw std::runtime_error("NEC2 alpha.20 reference export supports ground plane z=0 only");
    }

    std::unordered_map<std::string, int> tags;
    for (std::size_t i = 0; i < project.wires.size(); ++i) tags.emplace(project.wires[i].id, static_cast<int>(i + 1));

    std::ostringstream out;
    out << std::scientific << std::setprecision(9);
    out << "CM EMMana-Next NEC2 reference export\n";
    out << "CM Project: " << project.name << "\n";
    out << "CM Schema: " << project.schema_version << "\n";
    out << "CM Own ground model: " << project.ground.model << "\n";
    if (project.ground.model == "homogeneous-halfspace-image-v1") {
        out << "CM NOTE: independent NEC2 reference uses GN 2 Sommerfeld/Norton, not EMMana-Next image approximation\n";
    }
    out << "CE\n";

    for (std::size_t i = 0; i < project.wires.size(); ++i) {
        const auto& w = project.wires[i];
        const int tag = static_cast<int>(i + 1);
        out << "CM WIRE " << tag << " = " << w.id << "\n";
        out << "GW " << tag << ' ' << w.segments << ' '
            << w.start.x << ' ' << w.start.y << ' ' << w.start.z << ' '
            << w.end.x << ' ' << w.end.y << ' ' << w.end.z << ' '
            << w.radius_m << "\n";
    }

    if (project.ground.model == "free-space") {
        out << "GE 0\n";
    } else {
        out << "GE 1\n";
        if (project.ground.model == "pec-image-v1") {
            out << "GN 1 0 0 0\n";
        } else if (project.ground.model == "homogeneous-halfspace-image-v1") {
            // Deliberately use the higher-fidelity Sommerfeld/Norton engine as an
            // independent reference. Do not set a strict acceptance delta until
            // this path has actually run in networked CI.
            out << "GN 2 0 0 0 "
                << project.ground.relative_permittivity << ' '
                << project.ground.conductivity_s_per_m << "\n";
        } else {
            throw std::runtime_error("Unsupported ground model during NEC2 export: " + project.ground.model);
        }
    }

    for (const auto& feed : project.feeds) {
        const auto it = tags.find(feed.wire_id);
        if (it == tags.end()) throw std::runtime_error("Feed references unknown wire during NEC2 export: " + feed.wire_id);
        out << "EX 0 " << it->second << ' ' << (feed.segment + 1) << " 0 "
            << feed.voltage_v.real() << ' ' << feed.voltage_v.imag() << "\n";
    }

    const double mhz = project.frequency_hz / 1.0e6;
    out << "FR 0 1 0 0 " << mhz << " 0\n";
    out << "XQ\n";
    out << "EN\n";
    return out.str();
}

void write_nec2_deck(const Project& project, const std::filesystem::path& path) {
    std::ofstream out(path);
    if (!out) throw std::runtime_error("Cannot create NEC2 deck: " + path.string());
    out << export_nec2_deck(project);
}

Nec2ParsedOutput parse_nec2_output(std::string_view text) {
    Nec2ParsedOutput result;
    const std::string source(text);
    const std::regex frequency_re(R"(FREQUENCY\s*=\s*([+-]?[0-9.]+(?:[Ee][+-]?[0-9]+)?)\s+MHZ)", std::regex::icase);
    std::smatch fm;
    if (std::regex_search(source, fm, frequency_re)) result.frequency_hz = parse_num(fm[1].str()) * 1.0e6;

    const std::string marker = "ANTENNA INPUT PARAMETERS";
    std::size_t pos = 0;
    while ((pos = source.find(marker, pos)) != std::string::npos) {
        const std::size_t next = source.find("CURRENTS AND LOCATION", pos);
        const std::size_t end = next == std::string::npos ? std::min(source.size(), pos + 6000) : next;
        std::istringstream block(source.substr(pos, end - pos));
        std::string line;
        while (std::getline(block, line)) {
            line = trim(line);
            if (line.empty()) continue;
            if (!std::isdigit(static_cast<unsigned char>(line.front())) && line.front() != '-' && line.front() != '+') continue;
            const std::regex glued(R"(([0-9])([+-])(?=[0-9.]))");
            line = std::regex_replace(line, glued, "$1 $2");
            std::istringstream ls(line);
            std::vector<std::string> token;
            for (std::string t; ls >> t;) token.push_back(t);
            if (token.size() < 11) continue;
            try {
                Nec2FeedResult f;
                std::size_t idx = 0;
                f.tag = std::stoi(token[idx++]);
                if (idx < token.size() && token[idx] == "*") ++idx;
                if (idx >= token.size()) continue;
                f.segment = std::stoi(token[idx++]);
                if (token.size() < idx + 9) continue;
                const double vre = parse_num(token[idx++]);
                const double vim = parse_num(token[idx++]);
                const double ire = parse_num(token[idx++]);
                const double iim = parse_num(token[idx++]);
                const double zre = parse_num(token[idx++]);
                const double zim = parse_num(token[idx++]);
                const double yre = parse_num(token[idx++]);
                const double yim = parse_num(token[idx++]);
                const double power = parse_num(token[idx++]);
                f.voltage_v = {vre, vim};
                f.current_a = {ire, iim};
                f.impedance_ohm = {zre, zim};
                f.admittance_s = {yre, yim};
                f.power_w = power;
                result.feeds.push_back(f);
            } catch (const std::exception&) {
            }
        }
        pos = end;
    }
    return result;
}

Nec2ParsedOutput parse_nec2_output_file(const std::filesystem::path& path) {
    std::ifstream in(path);
    if (!in) throw std::runtime_error("Cannot open NEC2 output: " + path.string());
    std::ostringstream ss;
    ss << in.rdbuf();
    return parse_nec2_output(ss.str());
}

} // namespace emnext::reference
