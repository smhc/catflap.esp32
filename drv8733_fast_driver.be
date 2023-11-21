import catflap
import mqtt
import string

class motor_limiter
    # PWMFrequency 400
    var fast_loop
    var target_state
    var speed
    var brake_counter
    var wake_counter
    var abort_counter
    var state_machine
  
    var enable_pin
    var sensor_enable_pin
    var motor_bwd_pin
    var motor_fwd_pin
    var limit_pin
    var hitmax

    var curtime
  
    def alter_speed()
      if self.hitmax == 1
        self.speed -= 5
      else
        self.speed += 5
      end
      if self.speed >= 1020
          self.hitmax = 1
          self.speed = 1020
      end
      if (self.speed < 850)
          self.speed = 850
      end
      gpio.set_pwm(self.motor_fwd_pin, self.speed)
    end

    def loop()
      self.abort_counter += 1
      if self.abort_counter > 350
         print("abort; state ", self.state_machine, self.speed)
         mqtt.publish("catflap/lasterror", string.format("aborted %s", self.curtime), true)
         self.state_machine = 99
         self.destroy()
         return
      end
  
      if self.state_machine == 0
          self.speed = 850
          print("init state ", self.state_machine, self.abort_counter)
          gpio.digital_write(self.enable_pin, 1)
          gpio.digital_write(self.sensor_enable_pin, 1)
          self.wake_counter = 0
          self.state_machine += 1
          return
      elif self.state_machine == 1
        if self.wake_counter > 25 
            self.wake_counter = 0
            self.state_machine += 1
            return
        end
        self.wake_counter += 1
        return
      elif self.state_machine == 2
          var readpin = gpio.digital_read(self.limit_pin)
          if readpin != self.target_state
              self.state_machine += 1
              print("begin state ", self.state_machine, self.abort_counter, self.speed)
              return
          end
          self.alter_speed()
          return
      elif self.state_machine == 3
          var readpin = gpio.digital_read(self.limit_pin)
          if readpin == self.target_state
              # brakes
              gpio.digital_write(self.motor_bwd_pin, 1)
              self.state_machine += 1
              print("target state ", self.state_machine, self.abort_counter, self.speed)

              mqtt.publish("catflap/lockstatus", string.format("%s %s", self.target_state ? "locked" : "unlocked", self.curtime), true)
              self.brake_counter = 0
              return
          end
          self.alter_speed()
          return
      elif self.state_machine == 4
          self.brake_counter += 1
          if self.brake_counter >= 20
              self.brake_counter = 0
              self.state_machine += 1
              print("brake state ", self.state_machine, self.abort_counter, self.speed)
              var readpin = gpio.digital_read(self.limit_pin)
              if readpin != self.target_state
                  # try again if not in the right state
                  self.shutdown()
                  self.state_machine = 0
                  print("try again state ", self.state_machine, self.abort_counter)
                  mqtt.publish("catflap/lasterror", string.format("retried %s", self.curtime), true)
              else
                print("end state ", self.state_machine, self.abort_counter, self.speed)
                self.destroy()
                return
              end
          end
          return
      else
          print("unknown state", self.state_machine)
          self.destroy()
      end
    end
    
    def go(state)
      self.target_state = state
      self.abort_counter = 0
      self.state_machine = 0
      self.hitmax = 0
      self.curtime = tasmota.time_str(tasmota.rtc()["local"])
      gpio.digital_write(self.motor_bwd_pin, 0)
      gpio.set_pwm(self.motor_fwd_pin, 0)
      tasmota.add_fast_loop(self.fast_loop)
    end
  
    def shutdown()
      gpio.digital_write(self.enable_pin, 0)
      gpio.digital_write(self.sensor_enable_pin, 0)
      gpio.digital_write(self.motor_fwd_pin, 0)
      gpio.digital_write(self.motor_bwd_pin, 0)
    end
  
    def destroy()
      self.shutdown()
      tasmota.remove_fast_loop(self.fast_loop)
    end
  
    def flapclose()
      print("close")
      self.go(1)
    end
  
    def flapopen()
      print("open")
      self.go(0)
    end
  
    def init()
      print("motor limiter init")
      self.limit_pin = 8
      self.sensor_enable_pin = 7
      self.enable_pin = 10
      self.motor_bwd_pin = 3
      self.motor_fwd_pin = 4
      self.fast_loop = / -> self.loop()
    end
  end

  catflap.motor_limiter = motor_limiter