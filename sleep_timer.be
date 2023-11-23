import catflap
import mqtt
import string
import math

class sleep_timer
    var active
    var m
    var curtime
    var timestr

    def gosleep(sleeptime)
        if (self.active)
            if (sleeptime < 0)
                # Invalid sleep time - try again in 10 mins
                mqtt.publish("catflap/lasterror", "Invalid sleep time", true)
                sleeptime = 600
            end
            print("sleeping for ", sleeptime)
            tasmota.cmd(string.format("DeepSleepTime %d", int(sleeptime)))
        else
            mqtt.publish("catflap/lasterror", "Attempt sleep while deactivated", true)
        end
    end

    def pausesleep()
        print("pause sleep mqtt")
        self.active = 0
        return true
    end

    def croncallback()
        print("crontab called")
    end

    def init()
        print('sleep timer init')
        # Open/close crontabs
        tasmota.add_cron("0 0 5 * * *", / -> self.croncallback(), 10)
        tasmota.add_cron("0 30 16 * * *", / -> self.croncallback(), 12)

        self.active = 1
        mqtt.unsubscribe("catflap/pausesleep")
        mqtt.subscribe("catflap/pausesleep", / -> self.pausesleep())
        self.m = catflap.motor_limiter()
    end

    def get_sleep_time(target)
        # offset for when deepsleep actually gets invoked
        var curtimeoff = self.curtime + 300

        var ds = 30
        for i: 10 .. 20000
            var wake = (((int(curtimeoff / ds)) + 1) * ds ) + (ds * 0.05)
            if (math.abs(wake - target) < 300)
                print('Sleep time: ', ds, i)
                mqtt.publish("catflap/nextwake", tasmota.time_str(int(wake)), true)
                return ds
            end
            if (i % 1000 == 0)
                tasmota.yield()
            end
            ds += 30
        end
        mqtt.publish("catflap/lasterror", string.format("no valid interval: %d, %d", curtimeoff, target), true)
        print('valid interval not found..')
        return -1
    end

    def process_wake()
        var sleeptime

        self.curtime = tasmota.rtc()["local"]
        self.timestr = tasmota.time_str(self.curtime)

        mqtt.publish("catflap/lastwake", self.timestr, true)
        
        # Need to disable sleeping to allow async timeout
        tasmota.cmd("DeepSleepTime 0")

        if (!self.active)
            tasmota.resp_cmnd_str("deactivated") 
            mqtt.publish("catflap/lasterror", string.format("sleep paused %s", self.timestr), true)
            return true
        end

        # Note this suffers from Y2K38 epochalypse
        var openstamp = tasmota.next_cron(10)
        var closestamp = tasmota.next_cron(12)

        mqtt.publish("catflap/nextopen", tasmota.time_str(openstamp), true)
        mqtt.publish("catflap/nextclose", tasmota.time_str(closestamp), true)

        var openmins  = (tasmota.time_dump(openstamp)["hour"] * 60) + tasmota.time_dump(openstamp)["min"]
        var closemins = (tasmota.time_dump(closestamp)["hour"] * 60) + tasmota.time_dump(closestamp)["min"]
        var curmins   = (tasmota.time_dump(self.curtime)["hour"] * 60) + tasmota.time_dump(self.curtime)["min"]

        if (math.abs(openmins - curmins) < 20)
            print("unlocking morning")
            mqtt.publish("catflap/lockstatus", string.format("unlocking %s, %d, %d", self.timestr, openmins, curmins), true)
            self.m.flapopen()
            sleeptime = self.get_sleep_time(closestamp)
        elif (math.abs(closemins - curmins) < 20)
            print("locking evening")
            mqtt.publish("catflap/lockstatus", string.format("locking %s, %d, %d", self.timestr, closemins, curmins), true)
            self.m.flapclose()
            sleeptime = self.get_sleep_time(openstamp)
        elif (openstamp < closestamp)
            # Should only occur when manually restarting out of hours
            mqtt.publish("catflap/lockstatus", string.format("locking %s, %d, %d", self.timestr, openstamp, closestamp), true)
            mqtt.publish("catflap/lasterror", string.format("outofhours %s, %d", self.timestr, curmins), true)
            self.m.flapclose()
            sleeptime = self.get_sleep_time(openstamp)
        else
            # Should only occur when manually restarting out of hours
            mqtt.publish("catflap/lockstatus", string.format("unlocking %s, %d, %d", self.timestr, openstamp, closestamp), true)
            mqtt.publish("catflap/lasterror", string.format("outofhours %s, %d", self.timestr, curmins), true)
            self.m.flapopen()
            sleeptime = self.get_sleep_time(closestamp)
        end
        mqtt.publish("catflap/sleeptime", string.format("%d", sleeptime), true)

        # Allow time for locking mechanism
        tasmota.set_timer(3000, / -> self.gosleep(sleeptime))
        return true
    end
end

catflap.sleep_timer = sleep_timer
