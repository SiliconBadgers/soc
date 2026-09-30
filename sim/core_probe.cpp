#include "sim_host.hpp"
int main(int argc,char **argv) {
    try {
        if(argc<2) throw std::runtime_error("usage: core_probe firmware.bin [latency] [grant_period]");
        SimHost sim(argv[1],argc>2?std::stoi(argv[2]):1,argc>3?std::stoi(argv[3]):1);
        auto boot=sim.cycles;
        std::cout << "{\"boot_cycles\":" << boot << ",\"commands\":[";
        const uint16_t ops[]={1,0x8002,0x8003,0x8004,0xffff,1};
        for(unsigned i=0;i<6;++i) {
            auto result=sim.submit(ops[i],i+1,8,4,16,i==5?0:1);
            if(result.sequence!=i+1 || result.status!=(i>=4?0x81:0x80))
                throw std::runtime_error("wrong terminal status or identity");
            if(i) std::cout << ',';
            std::cout << "{\"seq\":"<<result.sequence<<",\"status\":"<<result.status<<",\"cycles\":"<<result.cycles<<'}';
        }
        std::cout << "],\"doorbells\":"<<sim.doorbells<<",\"completions\":"<<sim.completions<<",\"pass\":true}\n";
        return 0;
    } catch(const std::exception &e) { std::cerr<<e.what()<<'\n';return 1; }
}
