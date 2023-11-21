import catflap
import mqtt
import string
import math

class sleep_timer
    var active
    var m
    def gosleep(sleeptime)
        mqtt.publish("catflap/lasterror", "Attempting to sleep", true)
        if (self.active)
            if (sleeptime < 0)
                # Invalid sleep time - try again in 10 mins
                mqtt.publish("catlap/lasterror", "invalid sleep time", true)
                sleeptime = 600
            end
            print("sleeping for ", sleeptime)
            tasmota.cmd(string.format("DeepSleepTime %d", int(sleeptime)))

            # if it gets to here it failed
            mqtt.publish("catlap/lasterror", string.format("command failed: DeepSleepTime %d", int(sleeptime)), true)
        else
            mqtt.publish("catlap/lasterror", "Attempt sleep while deactivated", true)
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
        var curtime = tasmota.rtc()["local"]

        var ds = 30
        for i: 10 .. 20000
            var wake = (((int(curtime / ds)) + 1) * ds ) + (ds * 0.05)
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
        mqtt.publish("catflap/lasterror", string.format("no valid interval: %d, %d", curtime, target), true)
        print('valid interval not found..')
        return -1
    end

    def process_wake()
        var curtime = tasmota.rtc()["local"]
        var sleeptime
        var timestr = tasmota.time_str(tasmota.rtc()["local"])

        mqtt.publish("catflap/lastwake", timestr, true)

        if (!self.active)
            tasmota.cmd("DeepSleepTime 0")
            tasmota.resp_cmnd_str("deactivated") 
            mqtt.publish("catlap/lasterror", "sleep paused", true)
            return true
        end

        # Note this suffers from Y2K38 epochalypse
        var openstamp = tasmota.next_cron(10)
        var closestamp = tasmota.next_cron(12)

        mqtt.publish("catflap/nextopen", tasmota.time_str(openstamp), true)
        mqtt.publish("catflap/nextclose", tasmota.time_str(closestamp), true)

        var openmins  = (tasmota.time_dump(openstamp)["hour"] * 60) + tasmota.time_dump(openstamp)["min"]
        var closemins = (tasmota.time_dump(closestamp)["hour"] * 60) + tasmota.time_dump(closestamp)["min"]
        var curmins   = (tasmota.time_dump(curtime)["hour"] * 60) + tasmota.time_dump(curtime)["min"]

        if (math.abs(openmins - curmins) < 20)
            print("unlocking morning")
            mqtt.publish("catflap/lockstatus", string.format("unlocking %s, %d, %d", timestr, openmins, curmins), true)
            self.m.flapopen()
            sleeptime = self.get_sleep_time(closestamp)
        elif (math.abs(closemins - curmins) < 20)
            print("locking evening")
            mqtt.publish("catflap/lockstatus", string.format("locking %s, %d, %d", openmins, closemins, curmins), true)
            self.m.flapclose()
            sleeptime = self.get_sleep_time(openstamp)
        elif (openstamp < closestamp)
            # Should only occur when manually restarting out of hours
            mqtt.publish("catflap/lockstatus", string.format("locking %s, %d, %d", openmins, closemins, curmins), true)
            self.m.flapclose()
            sleeptime = self.get_sleep_time(openstamp)
        else
            # Should only occur when manually restarting out of hours
            mqtt.publish("catflap/lockstatus", string.format("unlocking %s, %d, %d", timestr, openmins, curmins), true)
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