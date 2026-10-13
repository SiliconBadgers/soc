#pragma once
// Included after the selected probe's main has been renamed to host_probe_main.
extern "C" int run_probe(const char *firmware, const char *model, int latency,
                         int grant_period, int *status) {
    try {
        std::vector<std::string> values{"probe", firmware};
        if (ProbeUsesModel) {
            if (*model) values.emplace_back(model);
        } else {
            values.push_back(std::to_string(latency));
            values.push_back(std::to_string(grant_period));
        }
        std::vector<char *> args;
        for (auto &value : values) args.push_back(value.data());
        args.push_back(nullptr);
        *status = host_probe_main(int(values.size()), args.data());
        return 0;
    } catch (const DpiDisabled &) {
        svAckDisabledState();
        return 1;
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        *status = 1;
        return 0;
    }
}
