#include <cassert>
#include <cstring>
#include <iostream>
#include "rf_finder/sx1280_fusion/fusion3_protocol.h"
#include "rf_finder/sx1280_fusion/fusion3_controller.h"

using namespace rf_fusion3;

struct FakeRadio : RadioBackend {
    bool control=true, armed=false, started=false, aborted=false;
    bool enterControlMode() override { control=true; return true; }
    bool armRangingMaster(const char*,const char*) override { armed=true; return true; }
    bool armRangingSlave(const char*,const char*) override { return true; }
    bool startRanging() override { started=true; return true; }
    bool pollRange(RangeResult& out) override {
        if(!started) return false;
        out.raw_mm=42100; out.calibrated_mm=41800; out.sigma_mm=700;
        out.quality_milli=930; out.rssi_dbm=-65; out.tx_power_dbm=10;
        out.los=LosState::Los; out.calibration_id="CAL-1";
        started=false; return true;
    }
    void abortRanging() override { aborted=true; }
};

int main() {
    char buf[512];
    RangeResult r;
    r.session_id="S1";r.sequence=7;r.from="A";r.to="T";r.target_id="T-001";
    r.timestamp_ms=1234;r.raw_mm=42400;r.calibrated_mm=42100;r.sigma_mm=800;
    r.quality_milli=910;r.rssi_dbm=-68;r.tx_power_dbm=10;r.los=LosState::Los;
    r.calibration_id="CAL-1";r.flags="TEST";
    int n=formatRange(buf,sizeof(buf),r);
    assert(n>0);
    assert(std::strstr(buf,"F3,RANGE,S1,7,A,T,T-001")!=nullptr);

    auto cmd=parseHostCommand("F3,C,RANGE,A,T,3");
    assert(cmd.type==HostCommand::Type::Range);
    assert(std::strcmp(cmd.from,"A")==0);
    assert(std::strcmp(cmd.to,"T")==0);
    assert(cmd.count==3);

    FakeRadio radio;
    Controller c(radio);
    c.setSession("S1","T-001");
    assert(c.beginRange(cmd,1000));
    int reports=0;
    for(uint32_t t=1000;t<3000 && c.phase()!=RangingPhase::Idle;t+=10) {
        c.tick(t,[&](const RangeResult& rr){
            ++reports;
            assert(std::strcmp(rr.from,"A")==0);
            assert(std::strcmp(rr.to,"T")==0);
            assert(rr.calibrated_mm==41800);
            assert(std::strcmp(rr.target_id,"T-001")==0);
        });
    }
    assert(reports==3);
    assert(c.phase()==RangingPhase::Idle);
    std::cout << "fusion3 firmware protocol/controller OK\n";
    return 0;
}
