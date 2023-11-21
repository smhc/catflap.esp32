load('catflap.be')
load('drv8733_fast_driver.be')
load('sleep_timer.be')

import catflap
st = catflap.sleep_timer()
tasmota.add_cmd("ProcessWake", def(cmd, idx, payload)
        st.process_wake() ? tasmota.resp_cmnd_done() : tasmota.resp_cmnd_failed()
    end)
