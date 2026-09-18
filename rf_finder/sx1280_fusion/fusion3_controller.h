#pragma once
#include "fusion3_protocol.h"

namespace rf_fusion3 {

enum class RangingPhase : uint8_t {
    Idle=0,
    Control,
    Arm,
    SwitchToRanging,
    WaitResult,
    Report,
    ReturnToControl,
    Fault
};

struct RangingJob {
    char from[9] = {};
    char to[9] = {};
    char target_id[33] = {};
    uint16_t requested = 1;
    uint16_t completed = 0;
    uint32_t started_ms = 0;
};

class RadioBackend {
public:
    virtual ~RadioBackend() = default;
    virtual bool enterControlMode() = 0;
    virtual bool armRangingMaster(const char* peer_id,const char* target_id) = 0;
    virtual bool armRangingSlave(const char* peer_id,const char* target_id) = 0;
    virtual bool startRanging() = 0;
    virtual bool pollRange(RangeResult& out) = 0;
    virtual void abortRanging() = 0;
};

class Controller {
public:
    explicit Controller(RadioBackend& radio):radio_(radio){}

    bool beginRange(const HostCommand& cmd,uint32_t now_ms) {
        if(cmd.type!=HostCommand::Type::Range || phase_!=RangingPhase::Idle)return false;
        std::snprintf(job_.from,sizeof(job_.from),"%s",cmd.from);
        std::snprintf(job_.to,sizeof(job_.to),"%s",cmd.to);
        job_.requested=cmd.count;
        job_.completed=0;
        job_.started_ms=now_ms;
        phase_=RangingPhase::Control;
        deadline_ms_=now_ms+1500;
        return true;
    }

    void stop() {
        radio_.abortRanging();
        radio_.enterControlMode();
        phase_=RangingPhase::Idle;
    }

    template<class ReportFn>
    void tick(uint32_t now_ms,ReportFn report) {
        if(phase_==RangingPhase::Idle)return;
        if(now_ms>deadline_ms_ && phase_!=RangingPhase::Report){fault();return;}
        switch(phase_) {
            case RangingPhase::Control:
                if(!radio_.enterControlMode()){fault();break;}
                phase_=RangingPhase::Arm;deadline_ms_=now_ms+500;break;
            case RangingPhase::Arm:
                if(!radio_.armRangingMaster(job_.to,job_.target_id)){fault();break;}
                phase_=RangingPhase::SwitchToRanging;deadline_ms_=now_ms+500;break;
            case RangingPhase::SwitchToRanging:
                if(!radio_.startRanging()){fault();break;}
                phase_=RangingPhase::WaitResult;deadline_ms_=now_ms+1000;break;
            case RangingPhase::WaitResult: {
                RangeResult rr;
                if(radio_.pollRange(rr)){
                    rr.sequence=++sequence_;
                    rr.timestamp_ms=now_ms;
                    rr.from=job_.from;rr.to=job_.to;
                    rr.target_id=job_.target_id[0]?job_.target_id:"T-001";
                    report(rr);
                    ++job_.completed;
                    phase_=RangingPhase::Report;
                }
                break;
            }
            case RangingPhase::Report:
                phase_=RangingPhase::ReturnToControl;deadline_ms_=now_ms+500;break;
            case RangingPhase::ReturnToControl:
                if(!radio_.enterControlMode()){fault();break;}
                if(job_.completed<job_.requested){phase_=RangingPhase::Arm;deadline_ms_=now_ms+500;}
                else phase_=RangingPhase::Idle;
                break;
            case RangingPhase::Fault:
                stop();
                break;
            default: break;
        }
    }

    RangingPhase phase()const{return phase_;}
    const RangingJob& job()const{return job_;}

private:
    void fault(){radio_.abortRanging();phase_=RangingPhase::Fault;}
    RadioBackend& radio_;
    RangingPhase phase_=RangingPhase::Idle;
    RangingJob job_{};
    uint32_t deadline_ms_=0;
    uint32_t sequence_=0;
};

} // namespace rf_fusion3
