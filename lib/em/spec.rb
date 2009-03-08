require File.dirname(__FILE__) + '/../ext/fiber18'

require 'bacon'

class Bacon::FiberedContext < Bacon::Context
  def it *args
    super{
      if block_given?
        yield
        Fiber.yield
      end
    }
  end

  def done
    EM.next_tick{
      :done.should == :done
      $bacon_fiber.resume if $bacon_fiber
    }
  end

  def timeout sec
    EM.add_timer(sec) {
      # TODO: die with some timeout notice
      EM.stop
    }
  end

end

require 'eventmachine'

module EventMachine
  def self.spec *args, &blk
    raise ArgumentError, 'block required' unless block_given?
    raise 'EventMachine reactor already running' if EM.reactor_running?

    EM.run{
      Bacon.summary_on_exit
      ($bacon_fiber = Fiber.new{
                        Bacon::FiberedContext.new(args.join(' '), &blk).run
                        EM.stop_event_loop
                      }).resume
    }
  end
  class << self; alias :describe :spec; end
end

if __FILE__ == $0

  describe 'Bacon' do
    should 'work as normal outside EM.describe' do
      1.should == 1
    end
  end

  EM.describe EventMachine do
    should 'work' do
      done
    end

    should 'have timers' do
      start = Time.now

      EM.add_timer(0.5){
        (Time.now-start).should.be.close 0.5, 0.1
        done
      }
    end

    should 'have periodic timers' do
      num = 0
      start = Time.now

      timer = EM.add_periodic_timer(0.5){
        if (num += 1) == 2
          (Time.now-start).should.be.close 1.0, 0.1
          EM.__send__ :cancel_timer, timer
          done
        end
      }
    end

    should 'have deferrables' do
      defr = EM::DefaultDeferrable.new
      defr.timeout(1)
      defr.errback{
        done
      }
    end
  end

  EM.describe "EventMachine with a timeout" do
    timeout 1

    should "run this" do
      1.should == 1
      done
    end
    
    EM.add_timer(2) {
      should "timeout before getting here" do
        false.should == true
      end
      done
    }
    
    should "bail in the middle of this" do
      1.should == 1
      EM.add_timer(2) {
        false.should == true
        done
      }
    end
  end

end