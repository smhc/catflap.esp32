import catflap
import mqtt
import string
import math

class sleep_timer
    var active
    var m
    var curtime
    var timestr

    def gosleep()
        if (self.active)
            tasmota.cmd("Restart 9")
        else
            mqtt.publish("catflap/lasterror", "Attempt sleep while deactivated", true)
        end
    end

    def pausesleep()
        print("pause sleep mqtt")
        self.active = 0
        return true
    end

    def init()
        print('sleep timer init')
        self.active = 1
        mqtt.unsubscribe("catflap/pausesleep")
        mqtt.subscribe("catflap/pausesleep", / -> self.pausesleep())
        self.m = catflap.motor_limiter()
    end

    def process_wake()
        self.curtime = tasmota.rtc()["local"]
        self.timestr = tasmota.time_str(self.curtime)

        mqtt.publish("catflap/lastwake", self.timestr, true)
        if (!self.active)
            tasmota.resp_cmnd_str("deactivated") 
            mqtt.publish("catflap/lasterror", string.format("sleep paused %s", self.timestr), true)
            return true
        end
        var curmins   = (tasmota.time_dump(self.curtime)["hour"] * 60) + tasmota.time_dump(self.curtime)["min"]
        if (curmins > 720) # After midday
            mqtt.publish("catflap/lockstatus", string.format("locking %s", self.timestr), true)
            self.m.flapclose()
        else
            mqtt.publish("catflap/lockstatus", string.format("unlocking %s", self.timestr), true)
            self.m.flapopen()
        end

        # Allow time for locking mechanism
        tasmota.set_timer(3000, / -> self.gosleep())
        return true
    end
end

catflap.sleep_timer = sleep_timer
