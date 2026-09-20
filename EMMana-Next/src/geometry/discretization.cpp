#include "emnext/geometry/discretization.hpp"
#include <algorithm>
#include <cmath>
#include <stdexcept>
namespace emnext::geometry { namespace {
Vec3 add(const Vec3& a,const Vec3& b){return {a.x+b.x,a.y+b.y,a.z+b.z};}
Vec3 sub(const Vec3& a,const Vec3& b){return {a.x-b.x,a.y-b.y,a.z-b.z};}
Vec3 mul(const Vec3& a,double s){return {a.x*s,a.y*s,a.z*s};}
double norm(const Vec3& a){return std::sqrt(a.x*a.x+a.y*a.y+a.z*a.z);}
bool coincident(const Vec3& a,const Vec3& b){constexpr double tol_m=1e-9; return norm(sub(a,b))<=tol_m;}
}
DiscretizedModel discretize(const Project& project){
    DiscretizedModel out; std::size_t total=0; for(const auto& wire:project.wires) total+=static_cast<std::size_t>(wire.segments); out.segments.reserve(total);
    for(std::size_t wi=0;wi<project.wires.size();++wi){const auto& wire=project.wires[wi]; if(wire.segments<1) throw std::runtime_error("Cannot discretize wire with no segments: "+wire.id); const Vec3 delta=sub(wire.end,wire.start); const double length=norm(delta); if(!(length>0.0)) throw std::runtime_error("Cannot discretize zero-length wire: "+wire.id); const Vec3 tangent=mul(delta,1.0/length); const Vec3 step=mul(delta,1.0/static_cast<double>(wire.segments)); const double seg_len=length/static_cast<double>(wire.segments);
        for(int si=0;si<wire.segments;++si){const Vec3 p0=add(wire.start,mul(step,static_cast<double>(si))); const Vec3 p1=add(wire.start,mul(step,static_cast<double>(si+1))); const Vec3 center=mul(add(p0,p1),0.5); out.segments.push_back(Segment{out.segments.size(),wi,wire.id,si,p0,p1,center,tangent,seg_len,wire.radius_m});}
    }
    for(std::size_t wi=0;wi<project.wires.size();++wi){const auto& wire=project.wires[wi]; const auto first=std::find_if(out.segments.begin(),out.segments.end(),[&](const Segment&s){return s.wire_index==wi&&s.local_index==0;}); const auto last=std::find_if(out.segments.begin(),out.segments.end(),[&](const Segment&s){return s.wire_index==wi&&s.local_index==wire.segments-1;}); if(first==out.segments.end()||last==out.segments.end()) throw std::runtime_error("Wire endpoint segment missing after discretization: "+wire.id);
        const auto add_endpoint=[&](const Vec3& position,const Segment& seg,bool at_start){auto node=std::find_if(out.endpoint_nodes.begin(),out.endpoint_nodes.end(),[&](const JunctionNode&n){return coincident(n.position,position);}); if(node==out.endpoint_nodes.end()){out.endpoint_nodes.push_back(JunctionNode{out.endpoint_nodes.size(),position,{}}); node=std::prev(out.endpoint_nodes.end());} node->incident_endpoints.push_back(SegmentEndpointRef{seg.global_index,wi,wire.id,at_start});}; add_endpoint(wire.start,*first,true); add_endpoint(wire.end,*last,false);
    }
    std::vector<std::size_t> parent(project.wires.size()); for(std::size_t i=0;i<parent.size();++i) parent[i]=i;
    const auto find_root=[&](std::size_t x,auto&&self)->std::size_t{if(parent[x]==x)return x; parent[x]=self(parent[x],self); return parent[x];};
    const auto unite=[&](std::size_t a,std::size_t b){const auto ra=find_root(a,find_root); const auto rb=find_root(b,find_root); if(ra!=rb) parent[rb]=ra;};
    for(const auto& node:out.endpoint_nodes){if(node.incident_endpoints.size()<2)continue; const auto first_wire=node.incident_endpoints.front().wire_index; for(std::size_t i=1;i<node.incident_endpoints.size();++i)unite(first_wire,node.incident_endpoints[i].wire_index);}
    out.wire_conductor_component.resize(project.wires.size()); std::vector<std::size_t> root_to_component(project.wires.size(),static_cast<std::size_t>(-1)); std::size_t next_component=0; for(std::size_t wi=0;wi<project.wires.size();++wi){const auto root=find_root(wi,find_root); if(root_to_component[root]==static_cast<std::size_t>(-1)) root_to_component[root]=next_component++; out.wire_conductor_component[wi]=root_to_component[root];}
    out.feed_segment_global_indices.reserve(project.feeds.size()); for(const auto& feed:project.feeds){const auto wire_it=std::find_if(project.wires.begin(),project.wires.end(),[&](const Wire&w){return w.id==feed.wire_id;}); if(wire_it==project.wires.end()) throw std::runtime_error("Feed references unknown wire: "+feed.wire_id); const std::size_t wi=static_cast<std::size_t>(std::distance(project.wires.begin(),wire_it)); const auto seg_it=std::find_if(out.segments.begin(),out.segments.end(),[&](const Segment&s){return s.wire_index==wi&&s.local_index==feed.segment;}); if(seg_it==out.segments.end()) throw std::runtime_error("Feed segment was not found after discretization"); out.feed_segment_global_indices.push_back(seg_it->global_index);}
    return out;
}
}
