#include "emnext/core/model_tools.hpp"
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iomanip>
#include <numbers>
#include <sstream>
#include <string>
namespace emnext { namespace {
constexpr double c0=299792458.0; constexpr double mu0=1.25663706212e-6;
void fnv1a_append(std::uint64_t&hash,const std::string&s){constexpr std::uint64_t prime=1099511628211ULL; for(const unsigned char ch:s){hash^=static_cast<std::uint64_t>(ch);hash*=prime;}}
std::string canonical_double(double value){std::ostringstream os;os<<std::scientific<<std::setprecision(17)<<value;return os.str();}
bool ground_enabled(const GroundModel& g){return g.model!="free-space";}
}
double wire_length_m(const Wire&wire){const double dx=wire.end.x-wire.start.x,dy=wire.end.y-wire.start.y,dz=wire.end.z-wire.start.z;return std::sqrt(dx*dx+dy*dy+dz*dz);}
double wavelength_m(double frequency_hz){return c0/frequency_hz;}
const char* model_hash_algorithm_id() noexcept{return "fnv1a64-emnext-model-v5";}
ModelCheck check_model(const Project&project){
    ModelCheck check; if(!(project.frequency_hz>0.0)){check.errors.emplace_back("Frequency must be positive");return check;} const double lambda=wavelength_m(project.frequency_hz);
    const bool valid_ground=project.ground.model=="free-space"||project.ground.model=="pec-image-v1"||project.ground.model=="homogeneous-halfspace-image-v1";
    if(!valid_ground) check.errors.emplace_back("Unsupported ground model: "+project.ground.model);
    if(project.ground.model=="homogeneous-halfspace-image-v1"){
        if(!(project.ground.relative_permittivity>=1.0)) check.errors.emplace_back("Ground relative_permittivity must be >= 1");
        if(project.ground.conductivity_s_per_m<0.0) check.errors.emplace_back("Ground conductivity_s_per_m must be >= 0");
        check.warnings.emplace_back("Alpha.20 finite ground uses a homogeneous planar reflection/image approximation, not Sommerfeld/Norton");
    }
    if(project.ground.model=="pec-image-v1") check.warnings.emplace_back("PEC ground uses the image-current boundary model above a horizontal plane");
    for(const auto&wire:project.wires){const double length=wire_length_m(wire); if(!(length>0.0)){check.errors.emplace_back("Wire "+wire.id+" has zero length");continue;} if(!(wire.radius_m>0.0)){check.errors.emplace_back("Wire "+wire.id+" has non-positive radius");continue;} if(wire.segments<3){check.errors.emplace_back("Wire "+wire.id+" has fewer than 3 segments");continue;} const double segment=length/static_cast<double>(wire.segments); if(segment>lambda/10.0)check.warnings.emplace_back("Wire "+wire.id+": segment length exceeds lambda/10"); if(segment<2.0*wire.radius_m)check.warnings.emplace_back("Wire "+wire.id+": segment length is below 2 radii; thin-wire discretization may be poor"); if(wire.radius_m>lambda/50.0)check.warnings.emplace_back("Wire "+wire.id+": radius is electrically thick for the initial thin-wire solver");
        if(wire.conductivity_s_per_m>0.0){const double omega=2.0*std::numbers::pi_v<double>*project.frequency_hz;const double skin_depth=std::sqrt(2.0/(omega*mu0*wire.conductivity_s_per_m));if(wire.radius_m<3.0*skin_depth)check.warnings.emplace_back("Wire "+wire.id+": radius is below 3 skin depths; surface-resistance loss approximation may be inaccurate");}
        if(ground_enabled(project.ground)){
            const bool start_terminal=std::any_of(project.feeds.begin(),project.feeds.end(),[&](const Feed&f){return f.wire_id==wire.id&&f.mode=="ground-terminal-start";});
            const bool end_terminal=std::any_of(project.feeds.begin(),project.feeds.end(),[&](const Feed&f){return f.wire_id==wire.id&&f.mode=="ground-terminal-end";});
            const auto endpoint_ok=[&](double z,bool terminal){const double dz=z-project.ground.plane_z_m;return terminal?std::abs(dz)<=1e-9:dz>wire.radius_m;};
            if(!endpoint_ok(wire.start.z,start_terminal)||!endpoint_ok(wire.end.z,end_terminal))check.errors.emplace_back("Wire "+wire.id+" violates ground clearance/terminal semantics");
        }
    }
    for(const auto&feed:project.feeds){
        const auto it=std::find_if(project.wires.begin(),project.wires.end(),[&](const Wire&w){return w.id==feed.wire_id;});
        if(it==project.wires.end()){check.errors.emplace_back("Feed references unknown wire "+feed.wire_id);continue;}
        if(feed.mode=="segment"){if(feed.segment<0||feed.segment>=it->segments)check.errors.emplace_back("Feed segment index is outside wire "+feed.wire_id);}
        else if(feed.mode=="ground-terminal-start"||feed.mode=="ground-terminal-end"){
            if(project.ground.model!="pec-image-v1")check.errors.emplace_back("Ground-terminal feed requires PEC ground");
            const double z=feed.mode=="ground-terminal-start"?it->start.z:it->end.z;
            if(std::abs(z-project.ground.plane_z_m)>1e-9)check.errors.emplace_back("Ground-terminal feed endpoint is not on ground plane");
        }else check.errors.emplace_back("Unsupported feed mode: "+feed.mode);
    }
    return check;
}
std::string stable_model_hash(const Project&project){std::uint64_t hash=14695981039346656037ULL;fnv1a_append(hash,std::string(model_hash_algorithm_id())+"|");fnv1a_append(hash,canonical_double(project.frequency_hz));
    fnv1a_append(hash,"|ground|");fnv1a_append(hash,project.ground.model);fnv1a_append(hash,canonical_double(project.ground.plane_z_m));fnv1a_append(hash,canonical_double(project.ground.relative_permittivity));fnv1a_append(hash,canonical_double(project.ground.conductivity_s_per_m));
    for(const auto&w:project.wires){fnv1a_append(hash,"|wire|");fnv1a_append(hash,w.id);fnv1a_append(hash,canonical_double(w.start.x));fnv1a_append(hash,canonical_double(w.start.y));fnv1a_append(hash,canonical_double(w.start.z));fnv1a_append(hash,canonical_double(w.end.x));fnv1a_append(hash,canonical_double(w.end.y));fnv1a_append(hash,canonical_double(w.end.z));fnv1a_append(hash,canonical_double(w.radius_m));fnv1a_append(hash,std::to_string(w.segments));fnv1a_append(hash,canonical_double(w.conductivity_s_per_m));}
    for(const auto&load:project.loads){fnv1a_append(hash,"|load|");fnv1a_append(hash,load.id);fnv1a_append(hash,load.wire_id);fnv1a_append(hash,std::to_string(load.segment));fnv1a_append(hash,canonical_double(load.resistance_ohm));fnv1a_append(hash,canonical_double(load.inductance_h));fnv1a_append(hash,canonical_double(load.capacitance_f));}
    for(const auto&f:project.feeds){fnv1a_append(hash,"|feed|");fnv1a_append(hash,f.wire_id);fnv1a_append(hash,std::to_string(f.segment));fnv1a_append(hash,canonical_double(f.voltage_v.real()));fnv1a_append(hash,canonical_double(f.voltage_v.imag()));fnv1a_append(hash,canonical_double(f.source_span_m));fnv1a_append(hash,f.mode);}
    std::ostringstream os;os<<std::hex<<std::setfill('0')<<std::setw(16)<<hash;return os.str();}
}
