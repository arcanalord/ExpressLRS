#include "emnext/physics/wire_mom.hpp"
#include "emnext/core/model_tools.hpp"
#include "emnext/geometry/discretization.hpp"
#include "emnext/linalg/linear_solver.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <cstddef>
#include <limits>
#include <numbers>
#include <stdexcept>
#include <string>
#include <vector>

namespace emnext::physics { namespace {
constexpr double eps0=8.8541878128e-12; constexpr double mu0=1.25663706212e-6; constexpr double c0=299792458.0;
struct BasisPiece{std::size_t segment_global{};std::size_t wire_index{};std::size_t conductor_component{};Vec3 start;Vec3 end;Vec3 tangent;double length_m{};double radius_m{};bool rising{};double amplitude{1.0};double derivative_per_m{};};
struct BasisFunction{std::vector<BasisPiece> pieces;bool junction{};};
struct PreparedLoad{std::size_t segment_global{};Complex impedance_ohm{};double resistance_ohm{};std::string id;};
struct Quad8{static constexpr std::array<double,8>x{-0.96028985649753623168,-0.79666647741362673959,-0.52553240991632898582,-0.18343464249564980494,0.18343464249564980494,0.52553240991632898582,0.79666647741362673959,0.96028985649753623168};static constexpr std::array<double,8>w{0.10122853629037625915,0.22238103445337447054,0.31370664587788728734,0.36268378337836198297,0.36268378337836198297,0.31370664587788728734,0.22238103445337447054,0.10122853629037625915};};
struct Quad16{static constexpr std::array<double,16>x{-0.98940093499164993260,-0.94457502307323257608,-0.86563120238783174388,-0.75540440835500303390,-0.61787624440264374845,-0.45801677765722738634,-0.28160355077925891323,-0.09501250983763744019,0.09501250983763744019,0.28160355077925891323,0.45801677765722738634,0.61787624440264374845,0.75540440835500303390,0.86563120238783174388,0.94457502307323257608,0.98940093499164993260};static constexpr std::array<double,16>w{0.02715245941175409485,0.06225352393864789286,0.09515851168249278481,0.12462897125553387205,0.14959598881657673208,0.16915651939500253819,0.18260341504492358887,0.18945061045506849629,0.18945061045506849629,0.18260341504492358887,0.16915651939500253819,0.14959598881657673208,0.12462897125553387205,0.09515851168249278481,0.06225352393864789286,0.02715245941175409485};};
Vec3 add(const Vec3&a,const Vec3&b){return{a.x+b.x,a.y+b.y,a.z+b.z};} Vec3 sub(const Vec3&a,const Vec3&b){return{a.x-b.x,a.y-b.y,a.z-b.z};} Vec3 mul(const Vec3&a,double s){return{a.x*s,a.y*s,a.z*s};} double dot(const Vec3&a,const Vec3&b){return a.x*b.x+a.y*b.y+a.z*b.z;} double norm2(const Vec3&a){return dot(a,a);} Vec3 mirror_point(const Vec3&p,double z0){return{p.x,p.y,2.0*z0-p.z};} Vec3 image_tangent(const Vec3&t){return{-t.x,-t.y,t.z};}
struct CVec3{Complex x{};Complex y{};Complex z{};}; CVec3 add(const CVec3&a,const CVec3&b){return{a.x+b.x,a.y+b.y,a.z+b.z};} CVec3 mul(const Vec3&a,Complex s){return{a.x*s,a.y*s,a.z*s};} Complex dot(const Vec3&a,const CVec3&b){return a.x*b.x+a.y*b.y+a.z*b.z;} double norm2(const CVec3&a){return std::norm(a.x)+std::norm(a.y)+std::norm(a.z);}
bool ground_enabled(const GroundModel&g){return g.model!="free-space";}
Complex ground_reflection_strength(const GroundModel&g,double omega){if(g.model=="free-space")return{0,0};if(g.model=="pec-image-v1")return{1,0};const Complex epsc{g.relative_permittivity,-g.conductivity_s_per_m/(omega*eps0)};return(epsc-Complex{1,0})/(epsc+Complex{1,0});}
std::string ground_settings_id(const GroundModel&g){if(g.model=="free-space")return"ground=free-space";if(g.model=="pec-image-v1")return"ground=pec-image-v1";return"ground=homogeneous-halfspace-image-v1";}
Vec3 point_on_piece(const BasisPiece&p,double t){return add(p.start,mul(sub(p.end,p.start),t));} double shape(const BasisPiece&p,double t){return p.amplitude*(p.rising?t:(1.0-t));}
double shape_integral_on_interval(const BasisPiece&p,double ta,double tb){ta=std::clamp(ta,0.0,1.0);tb=std::clamp(tb,0.0,1.0);if(!(tb>ta))return 0.0;const double sq=0.5*(tb*tb-ta*ta);const double n=p.rising?sq:((tb-ta)-sq);return p.amplitude*n*p.length_m;}
double basis_integral_over_wire_span(const BasisFunction&basis,std::size_t wi,const Wire&wire,double sa,double sb){const Vec3 axis_vec=sub(wire.end,wire.start);const double wl=std::sqrt(norm2(axis_vec));if(!(wl>0))return 0;const Vec3 axis=mul(axis_vec,1.0/wl);double total=0;for(const auto&piece:basis.pieces){if(piece.wire_index!=wi)continue;double s0=dot(sub(piece.start,wire.start),axis),s1=dot(sub(piece.end,wire.start),axis);if(s1<s0)std::swap(s0,s1);const double lo=std::max(s0,sa),hi=std::min(s1,sb);if(!(hi>lo))continue;const double den=s1-s0;if(!(den>0))continue;total+=shape_integral_on_interval(piece,(lo-s0)/den,(hi-s0)/den);}return total;}
std::vector<BasisFunction> make_basis(const Project& project, const geometry::DiscretizedModel& mesh) {
    std::vector<BasisFunction> basis;
    std::size_t off = 0;
    for (std::size_t wi = 0; wi < project.wires.size(); ++wi) {
        const auto& wire = project.wires[wi];
        for (int node = 1; node < wire.segments; ++node) {
            const auto& left = mesh.segments.at(off + static_cast<std::size_t>(node - 1));
            const auto& right = mesh.segments.at(off + static_cast<std::size_t>(node));
            basis.push_back(BasisFunction{{
                BasisPiece{left.global_index, wi, mesh.wire_conductor_component.at(wi), left.start, left.end, left.tangent, left.length_m, left.radius_m, true, 1.0, +1.0 / left.length_m},
                BasisPiece{right.global_index, wi, mesh.wire_conductor_component.at(wi), right.start, right.end, right.tangent, right.length_m, right.radius_m, false, 1.0, -1.0 / right.length_m}}, false});
        }
        off += static_cast<std::size_t>(wire.segments);
    }

    for (const auto& node : mesh.endpoint_nodes) {
        const std::size_t degree = node.incident_endpoints.size();
        if (degree < 2) continue;
        const auto make_piece = [&](const geometry::Segment& seg, const geometry::SegmentEndpointRef& ep, double amp) {
            const bool rising = !ep.at_start;
            const double base = rising ? +1.0 / seg.length_m : -1.0 / seg.length_m;
            return BasisPiece{seg.global_index, seg.wire_index, mesh.wire_conductor_component.at(seg.wire_index), seg.start, seg.end, seg.tangent, seg.length_m, seg.radius_m, rising, amp, amp * base};
        };
        const auto& refep = node.incident_endpoints.back();
        const auto& refseg = mesh.segments.at(refep.segment_global);
        const double refout = refep.at_start ? +1.0 : -1.0;
        for (std::size_t bi = 0; bi + 1 < degree; ++bi) {
            const auto& ep = node.incident_endpoints[bi];
            const auto& seg = mesh.segments.at(ep.segment_global);
            const double bout = ep.at_start ? +1.0 : -1.0;
            basis.push_back(BasisFunction{{make_piece(seg, ep, 1.0), make_piece(refseg, refep, -bout / refout)}, true});
        }
    }

    // A PEC-ground terminal is a half-rooftop basis. Its nonzero endpoint is
    // the physical feed terminal on the ground plane; the PEC image completes
    // the symmetric current basis below the plane.
    for (const auto& feed : project.feeds) {
        if (feed.mode != "ground-terminal-start" && feed.mode != "ground-terminal-end") continue;
        const auto wit = std::find_if(project.wires.begin(), project.wires.end(), [&](const Wire& w) { return w.id == feed.wire_id; });
        if (wit == project.wires.end()) throw std::runtime_error("Unknown ground-terminal wire: " + feed.wire_id);
        const std::size_t wi = static_cast<std::size_t>(std::distance(project.wires.begin(), wit));
        const bool at_start = feed.mode == "ground-terminal-start";
        const int local = at_start ? 0 : project.wires[wi].segments - 1;
        const auto seg_it = std::find_if(mesh.segments.begin(), mesh.segments.end(), [&](const auto& seg) {
            return seg.wire_index == wi && seg.local_index == local;
        });
        if (seg_it == mesh.segments.end()) throw std::runtime_error("Ground-terminal segment was not found");
        const bool rising = !at_start;
        const double derivative = rising ? +1.0 / seg_it->length_m : -1.0 / seg_it->length_m;
        basis.push_back(BasisFunction{{BasisPiece{seg_it->global_index, wi, mesh.wire_conductor_component.at(wi), seg_it->start, seg_it->end, seg_it->tangent, seg_it->length_m, seg_it->radius_m, rising, 1.0, derivative}}, false});
    }
    return basis;
}

Complex point_green_from_distance(double d,double k){if(!(d>0))throw std::runtime_error("Zero Green-function distance");return std::exp(Complex{0,-k*d})/(4.0*std::numbers::pi_v<double>*d);} 
Complex circumferential_exact_straight_green(const Vec3&r,const Vec3&rp,double k,double radius){const double dz2=norm2(sub(r,rp));const double pi=std::numbers::pi_v<double>;Complex sum{};for(int half=0;half<2;++half){const double a0=half==0?-pi:0.0,b0=half==0?0.0:pi;for(std::size_t q=0;q<Quad16::x.size();++q){const double phi=0.5*((b0-a0)*Quad16::x[q]+(b0+a0));const double wp=0.5*(b0-a0)*Quad16::w[q];const double R=std::sqrt(dz2+2.0*radius*radius*(1.0-std::cos(phi)));sum+=point_green_from_distance(R,k)*wp;}}return sum/(2.0*pi);} 
Complex green(const Vec3&r,const Vec3&rp,double k,bool same_cond,bool same_prim,double radius,WireKernelMode mode){if(same_prim&&mode==WireKernelMode::CircumferentialExactStraight)return circumferential_exact_straight_green(r,rp,k,radius);Vec3 d=sub(r,rp);double r2=norm2(d);if(same_cond&&mode==WireKernelMode::Reduced)r2+=radius*radius;if(!(r2>0))throw std::runtime_error("Coincident points on different wires are unsupported");return point_green_from_distance(std::sqrt(r2),k);} 
double surface_resistance_ohm(double f,double sigma){if(!(sigma>0))return 0;return std::sqrt(std::numbers::pi_v<double>*f*mu0/sigma);} double conductor_resistance_per_m(double f,double sigma,double radius){if(!(sigma>0)||!(radius>0))return 0;return surface_resistance_ohm(f,sigma)/(2.0*std::numbers::pi_v<double>*radius);} Complex series_rlc_impedance(const SeriesRlcLoad&l,double omega){Complex z{l.resistance_ohm,0};if(l.inductance_h>0)z+=Complex{0,omega*l.inductance_h};if(l.capacitance_f>0)z+=Complex{0,-1.0/(omega*l.capacitance_f)};return z;}
double basis_shape_on_segment_center(const BasisFunction&basis,std::size_t seg){double v=0;for(const auto&p:basis.pieces)if(p.segment_global==seg)v+=shape(p,0.5);return v;}
double basis_shape_at_terminal(const BasisFunction&basis,std::size_t seg,bool at_start){double v=0;const double t=at_start?0.0:1.0;for(const auto&p:basis.pieces)if(p.segment_global==seg)v+=shape(p,t);return v;} Complex segment_current_at_t(const std::vector<BasisFunction>&basis,const std::vector<Complex>&c,std::size_t seg,double t){Complex cur{};for(std::size_t bi=0;bi<basis.size();++bi)for(const auto&p:basis[bi].pieces)if(p.segment_global==seg)cur+=c[bi]*shape(p,t);return cur;}
Complex interaction(const BasisFunction&m,const BasisFunction&n,double omega,double k,WireKernelMode mode,const GroundModel&ground,Complex gr){Complex ia{},iphi{},ia_img{},iphi_img{};for(const auto&pm:m.pieces)for(const auto&pn:n.pieces){const bool same_cond=pm.conductor_component==pn.conductor_component;const bool same_prim=pm.wire_index==pn.wire_index;const double radius=0.5*(pm.radius_m+pn.radius_m);const double td=dot(pm.tangent,pn.tangent);const double itd=dot(pm.tangent,image_tangent(pn.tangent));for(std::size_t i=0;i<Quad8::x.size();++i){const double tm=0.5*(Quad8::x[i]+1.0),wm=0.5*Quad8::w[i]*pm.length_m;const Vec3 rm=point_on_piece(pm,tm);const double fm=shape(pm,tm);for(std::size_t j=0;j<Quad8::x.size();++j){const double tn=0.5*(Quad8::x[j]+1.0),wn=0.5*Quad8::w[j]*pn.length_m;const Vec3 rn=point_on_piece(pn,tn);const double fn=shape(pn,tn);const double weight=wm*wn;const Complex gd=green(rm,rn,k,same_cond,same_prim,radius,mode);ia+=td*fm*fn*gd*weight;iphi+=pm.derivative_per_m*pn.derivative_per_m*gd*weight;if(ground_enabled(ground)){const Vec3 rni=mirror_point(rn,ground.plane_z_m);const Complex gi=point_green_from_distance(std::sqrt(norm2(sub(rm,rni))),k);ia_img+=gr*itd*fm*fn*gi*weight;iphi_img+=(-gr)*pm.derivative_per_m*pn.derivative_per_m*gi*weight;}}}}
    const Complex j{0,1};return j*omega*mu0*(ia+ia_img)+(1.0/(j*omega*eps0))*(iphi+iphi_img);}
double conductor_loss_interaction(const BasisFunction&m,const BasisFunction&n,const Project&p){double total=0;for(const auto&pm:m.pieces){const auto&w=p.wires.at(pm.wire_index);const double rpm=conductor_resistance_per_m(p.frequency_hz,w.conductivity_s_per_m,w.radius_m);if(!(rpm>0))continue;for(const auto&pn:n.pieces){if(pm.segment_global!=pn.segment_global)continue;double integ=0;for(std::size_t q=0;q<Quad8::x.size();++q){const double t=0.5*(Quad8::x[q]+1.0),wt=0.5*Quad8::w[q]*pm.length_m;integ+=shape(pm,t)*shape(pn,t)*wt;}total+=rpm*integ;}}return total;}
Complex lumped_load_interaction(const BasisFunction&m,const BasisFunction&n,const std::vector<PreparedLoad>&loads){Complex total{};for(const auto&l:loads){const double fm=basis_shape_on_segment_center(m,l.segment_global);if(fm==0)continue;const double fn=basis_shape_on_segment_center(n,l.segment_global);if(fn==0)continue;total+=l.impedance_ohm*fm*fn;}return total;}
std::size_t wire_index_by_id(const Project&p,const std::string&id){for(std::size_t i=0;i<p.wires.size();++i)if(p.wires[i].id==id)return i;throw std::runtime_error("Unknown wire: "+id);} 
Complex segment_center_current(const geometry::DiscretizedModel&mesh,const std::vector<BasisFunction>&basis,const std::vector<Complex>&c,std::size_t wi,int si){const auto it=std::find_if(mesh.segments.begin(),mesh.segments.end(),[&](const auto&s){return s.wire_index==wi&&s.local_index==si;});if(it==mesh.segments.end())throw std::runtime_error("Segment outside wire");return segment_current_at_t(basis,c,it->global_index,0.5);} 
double junction_kcl_max_relative_error(const geometry::DiscretizedModel&mesh,const std::vector<BasisFunction>&basis,const std::vector<Complex>&c){double maxr=0;for(const auto&node:mesh.endpoint_nodes){if(node.incident_endpoints.size()<2)continue;Complex sum{};double mags=0;for(const auto&ep:node.incident_endpoints){Complex ic{};const double t=ep.at_start?0.0:1.0;for(std::size_t bi=0;bi<basis.size();++bi)for(const auto&p:basis[bi].pieces)if(p.segment_global==ep.segment_global)ic+=c[bi]*shape(p,t);sum+=(ep.at_start?+1.0:-1.0)*ic;mags+=std::abs(ic);}maxr=std::max(maxr,mags>0?std::abs(sum)/mags:0.0);}return maxr;}
CVec3 radiation_vector(const std::vector<BasisFunction>&basis,const std::vector<Complex>&c,const Vec3&rhat,double k,const GroundModel&ground,Complex gr){CVec3 total{};const Complex j{0,1};for(std::size_t bi=0;bi<basis.size();++bi){CVec3 bv{};for(const auto&p:basis[bi].pieces){Complex sd{},si{};for(std::size_t q=0;q<Quad8::x.size();++q){const double t=0.5*(Quad8::x[q]+1.0),wt=0.5*Quad8::w[q]*p.length_m;const Vec3 r=point_on_piece(p,t);sd+=shape(p,t)*std::exp(j*k*dot(rhat,r))*wt;if(ground_enabled(ground)){const Vec3 ri=mirror_point(r,ground.plane_z_m);si+=shape(p,t)*std::exp(j*k*dot(rhat,ri))*wt;}}bv=add(bv,mul(p.tangent,sd));if(ground_enabled(ground))bv=add(bv,mul(image_tangent(p.tangent),gr*si));}total=add(total,CVec3{c[bi]*bv.x,c[bi]*bv.y,c[bi]*bv.z});}return total;}
double radiation_intensity(const std::vector<BasisFunction>&basis,const std::vector<Complex>&c,const Vec3&rhat,double k,const GroundModel&ground,Complex gr){const double eta0=std::sqrt(mu0/eps0);const CVec3 f=radiation_vector(basis,c,rhat,k,ground,gr);const Complex par=dot(rhat,f);const CVec3 tr{f.x-rhat.x*par,f.y-rhat.y*par,f.z-rhat.z*par};return eta0*k*k*norm2(tr)/(32.0*std::numbers::pi_v<double>*std::numbers::pi_v<double>);} Vec3 direction(double theta,double phi){const double st=std::sin(theta);return{st*std::cos(phi),st*std::sin(phi),std::cos(theta)};}
}

ResultSet solve_wire_mom_experimental(const Project&project,const WireMomSettings&settings){
    if (settings.quadrature_order != 8) throw std::runtime_error("quadrature_order=8 only");
    if (project.feeds.size() != 1) throw std::runtime_error("exactly one voltage feed supported");
    const auto check = check_model(project);
    if (!check.ok()) throw std::runtime_error("Model-check failed before Wire-MoM solve");
    std::vector<std::string>kernel_warnings;if(settings.kernel_mode==WireKernelMode::Reduced){for(const auto&w:project.wires){const double seg=wire_length_m(w)/static_cast<double>(w.segments),ratio=seg/w.radius_m;if(ratio<2.0)throw std::runtime_error("Reduced-kernel refuses segment_length/radius < 2 on wire "+w.id);if(ratio<5.0)kernel_warnings.emplace_back("Wire "+w.id+": segment_length/radius < 5");}}else kernel_warnings.emplace_back("Circumferential exact kernel remains straight-primitive validation only");
    const auto mesh=geometry::discretize(project);for(const auto&node:mesh.endpoint_nodes)if(node.incident_endpoints.size()>3)throw std::runtime_error("junction degree > 3 unsupported");const auto basis=make_basis(project,mesh);if(basis.empty())throw std::runtime_error("no current unknowns");
    const double omega=2.0*std::numbers::pi_v<double>*project.frequency_hz,k=omega/c0;const Complex gr=ground_reflection_strength(project.ground,omega);
    std::vector<PreparedLoad>loads;for(const auto&l:project.loads){const auto wi=wire_index_by_id(project,l.wire_id);const auto it=std::find_if(mesh.segments.begin(),mesh.segments.end(),[&](const auto&s){return s.wire_index==wi&&s.local_index==l.segment;});if(it==mesh.segments.end())throw std::runtime_error("Load segment could not be mapped");loads.push_back(PreparedLoad{it->global_index,series_rlc_impedance(l,omega),l.resistance_ohm,l.id});}
    DenseMatrix z(basis.size(),basis.size());for(std::size_t m=0;m<basis.size();++m)for(std::size_t n=0;n<basis.size();++n)z(m,n)=interaction(basis[m],basis[n],omega,k,settings.kernel_mode,project.ground,gr)+Complex{conductor_loss_interaction(basis[m],basis[n],project),0}+lumped_load_interaction(basis[m],basis[n],loads);
    std::vector<Complex> v(basis.size(), Complex{});
    const auto& feed = project.feeds.front();
    const auto wi = wire_index_by_id(project, feed.wire_id);
    const auto& wire = project.wires[wi];
    std::vector<double> sw(basis.size(), 0.0);

    if (feed.mode == "segment") {
        if (feed.segment <= 0 || feed.segment >= wire.segments - 1) throw std::runtime_error("segment source must be on interior segment");
        const Vec3 wv = sub(wire.end, wire.start);
        const double wl = std::sqrt(norm2(wv));
        const double seglen = wl / static_cast<double>(wire.segments);
        const double fc = (static_cast<double>(feed.segment) + 0.5) * seglen;
        const double req = feed.source_span_m > 0 ? feed.source_span_m : seglen;
        const double fs = std::min(req, wl);
        const double sa = std::max(0.0, fc - 0.5 * fs);
        const double sb = std::min(wl, fc + 0.5 * fs);
        const double actual = sb - sa;
        if (!(actual > 0)) throw std::runtime_error("empty source span");
        for (std::size_t bi = 0; bi < basis.size(); ++bi) {
            sw[bi] = basis_integral_over_wire_span(basis[bi], wi, wire, sa, sb) / actual;
            v[bi] += feed.voltage_v * sw[bi];
        }
    } else {
        const bool at_start = feed.mode == "ground-terminal-start";
        const int local = at_start ? 0 : wire.segments - 1;
        const auto seg_it = std::find_if(mesh.segments.begin(), mesh.segments.end(), [&](const auto& seg) {
            return seg.wire_index == wi && seg.local_index == local;
        });
        if (seg_it == mesh.segments.end()) throw std::runtime_error("Ground-terminal source segment was not found");
        for (std::size_t bi = 0; bi < basis.size(); ++bi) {
            sw[bi] = basis_shape_at_terminal(basis[bi], seg_it->global_index, at_start);
            v[bi] += feed.voltage_v * sw[bi];
        }
    }
    const auto solver=linalg::make_default_solver();const auto c=solver->solve(z,v);const double residual=linalg::normalized_residual_inf(z,c,v);Complex ifeed{};for(std::size_t bi=0;bi<c.size();++bi)ifeed+=c[bi]*sw[bi];if(std::abs(ifeed)<1e-18)throw std::runtime_error("feed current zero");const Complex zin=feed.voltage_v/ifeed,yin=Complex{1,0}/zin,z0{settings.reference_impedance_ohm,0},gamma=(zin-z0)/(zin+z0);const double gm=std::abs(gamma),vswr=gm<1?(1+gm)/(1-gm):std::numeric_limits<double>::infinity();
    ResultSet result;result.solver_id=settings.kernel_mode==WireKernelMode::Reduced?"wire-mom-rooftop-galerkin-reduced-kernel-experimental":"wire-mom-rooftop-galerkin-circumferential-exact-straight-experimental";result.solver_version=settings.kernel_mode==WireKernelMode::Reduced?"0.5-ground-terminal":"0.5-validation-ground-terminal";result.linear_solver_backend=std::string(solver->name());result.linear_system_size=static_cast<int>(basis.size());result.linear_residual_relative=residual;result.junction_kcl_max_relative_error=junction_kcl_max_relative_error(mesh,basis,c);result.solver_settings_id="basis=graph-rooftop-junction-v1;kernel="+std::string(settings.kernel_mode==WireKernelMode::Reduced?"reduced":"circumferential-exact-straight")+";loss=skin-good-conductor-v1;loads=series-rlc-center-v1;"+ground_settings_id(project.ground)+";ground_reflection=complex-image-quasistatic-v1;feed="+feed.mode+";axial_quad=gauss8;z0_ohm="+std::to_string(settings.reference_impedance_ohm);result.model_hash_algorithm=model_hash_algorithm_id();result.model_hash=stable_model_hash(project);result.frequency_hz=project.frequency_hz;result.environment_model=project.ground.model;result.ground_plane_z_m=project.ground.plane_z_m;result.ground_relative_permittivity=project.ground.relative_permittivity;result.ground_conductivity_s_per_m=project.ground.conductivity_s_per_m;
    for (std::size_t widx = 0; widx < project.wires.size(); ++widx) {
        for (int si = 0; si < project.wires[widx].segments; ++si) {
            result.segment_currents_a.push_back(segment_center_current(mesh, basis, c, widx, si));
        }
    }
    result.feeds.push_back(FeedResult{feed.wire_id, feed.segment, zin, yin, gamma, vswr});
    result.accepted_power_w = 0.5 * std::real(feed.voltage_v * std::conj(ifeed));
    constexpr int phi_count=36;double radiated=0;for(std::size_t ui=0;ui<Quad16::x.size();++ui){double u=Quad16::x[ui],uw=Quad16::w[ui];if(ground_enabled(project.ground)){u=0.5*(u+1.0);uw*=0.5;}const double theta=std::acos(u);for(int pi=0;pi<phi_count;++pi){const double phi=2.0*std::numbers::pi_v<double>*(static_cast<double>(pi)+0.5)/static_cast<double>(phi_count);radiated+=radiation_intensity(basis,c,direction(theta,phi),k,project.ground,gr)*uw*(2.0*std::numbers::pi_v<double>/static_cast<double>(phi_count));}}result.radiated_power_w=radiated;
    double cond=0;for(const auto&s:mesh.segments){const auto&w=project.wires.at(s.wire_index);const double rpm=conductor_resistance_per_m(project.frequency_hz,w.conductivity_s_per_m,w.radius_m);if(!(rpm>0))continue;double i2=0;for(std::size_t q=0;q<Quad8::x.size();++q){const double t=0.5*(Quad8::x[q]+1.0),wt=0.5*Quad8::w[q]*s.length_m;i2+=std::norm(segment_current_at_t(basis,c,s.global_index,t))*wt;}cond+=0.5*rpm*i2;}double ld=0;for(const auto&l:loads){if(!(l.resistance_ohm>0))continue;ld+=0.5*l.resistance_ohm*std::norm(segment_current_at_t(basis,c,l.segment_global,0.5));}result.dissipated_power_w=cond+ld;
    result.ground_dissipated_power_w=0.0;if(project.ground.model=="homogeneous-halfspace-image-v1"){const double closure=result.accepted_power_w-result.radiated_power_w-result.dissipated_power_w;if(closure>0)result.ground_dissipated_power_w=closure;}
    const double outgoing=result.radiated_power_w+result.dissipated_power_w+result.ground_dissipated_power_w;result.efficiency=outgoing>0?result.radiated_power_w/outgoing:0;result.power_balance_relative_error=result.accepted_power_w>0?(outgoing-result.accepted_power_w)/result.accepted_power_w:0;
    for(int td=0;td<=180;td+=5){const double theta=static_cast<double>(td)*std::numbers::pi_v<double>/180.0;for(int pd=0;pd<360;pd+=10){const double phi=static_cast<double>(pd)*std::numbers::pi_v<double>/180.0;if(ground_enabled(project.ground)&&td>90){result.pattern.push_back(PatternSample{theta,phi,0,0});continue;}const double u=radiation_intensity(basis,c,direction(theta,phi),k,project.ground,gr);const double dlin=radiated>0?4.0*std::numbers::pi_v<double>*u/radiated:0;result.pattern.push_back(PatternSample{theta,phi,dlin*result.efficiency,dlin});}}
    result.warnings=check.warnings;if(!(residual<1e-10))result.warnings.emplace_back("Linear-system normalized residual exceeds 1e-10");result.warnings.insert(result.warnings.end(),kernel_warnings.begin(),kernel_warnings.end());if(settings.kernel_mode==WireKernelMode::Reduced)result.warnings.emplace_back("Experimental Wire-MoM uses a reduced-radius kernel; NEC/full-wave gate is still required");if(project.ground.model=="free-space")result.warnings.emplace_back("Environment is free space");else if(project.ground.model=="pec-image-v1")result.warnings.emplace_back("Alpha.20 PEC ground image boundary active; lower half-space pattern is suppressed");else{result.warnings.emplace_back("Alpha.20 finite ground uses complex image/reflection approximation; Sommerfeld/Norton is not implemented");result.warnings.emplace_back("Independent NEC2 finite-ground characterization shows non-negligible impedance error and large error at low antenna height; do not treat finite-ground results as release-authoritative");result.warnings.emplace_back("Alpha.20 ground dissipation is inferred by accepted-power closure, not a direct volumetric loss integral");}return result;
}
}
