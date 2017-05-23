shared_examples_for "awaiting the result of a deferred evaluation" do
  let(:conproc) { concurrent_proc(&wait_proc) }
  let(:evaluation) { conproc.call_detached }

  let(:wait_options) { {} }
  let(:evaluation_time) { 0.001 }
  let(:result) { :result }

  shared_examples_for "awaiting resumption" do |inside_concurrent_proc: false|
    context "when it is allowed to wait forever" do
      before { concurrently do
        wait evaluation_time
        resume
      end }
      it { is_expected.to eq result }
    end

    context "when limiting the wait time" do
      let(:wait_options) { { within: timeout_time, timeout_result: timeout_result } }
      let(:timeout_result) { :timeout_result }

      context "when the result arrives in time" do
        let(:timeout_time) { 5*evaluation_time }

        before { concurrently do
          wait evaluation_time
          resume
        end }

        let!(:after_timeout) { concurrent_proc{ wait timeout_time }.call_detached }

        it { is_expected.to eq result }

        # will raise an error if the timeout is not cancelled
        after { expect{ after_timeout.await_result }.not_to raise_error }
      end

      context "when the evaluation of the result is too slow" do
        let(:timeout_time) { 0.0 }

        context "when no timeout result is given" do
          before { wait_options.delete :timeout_result }

          if inside_concurrent_proc
            before { expect(conproc).to receive(:trigger).with(:error, (be_a(Concurrently::Proc::TimeoutError).
             and have_attributes message: "evaluation timed out after #{wait_options[:within]} second(s)")) }
          end
          it { is_expected.to raise_error Concurrently::Proc::TimeoutError, "evaluation timed out after #{wait_options[:within]} second(s)" }
        end

        context "when a timeout result is given" do
          let(:timeout_result) { :timeout_result }
          it { is_expected.to be :timeout_result }
        end
      end
    end
  end

  context "when originating inside a concurrent proc" do
    subject { evaluation.await_result }
    include_examples "awaiting resumption", inside_concurrent_proc: true

    describe "evaluating the concurrent evaluation while it is waiting" do
      # make sure the concurrent evaluation is started before evaluating it
      before { evaluation }

      before { concurrent_proc do
        # cancel the concurrent evaluation right away
        evaluation.conclude_with :intercepted

        # Wait after the event is triggered to make sure the concurrent evaluation
        # is not resumed then (i.e. watching the event is properly cancelled)
        wait evaluation_time
      end.call }

      it { is_expected.to be :intercepted }
    end

    describe "resumption before the concurrent proc has been started" do
      before { resume }
      it { is_expected.to be result }
    end
  end

  context "when originating outside a concurrent proc" do
    subject { wait_proc.call }
    let!(:evaluation) { Fiber.current }
    include_examples "awaiting resumption"
  end
end

shared_examples_for "#concurrently" do
  context "when called with arguments" do
    subject { @result }

    before { call(:arg1, :arg2) do |*args|
      @result = args
      @spec_fiber.schedule_resume!
    end }

    # We need a reference wait to ensure we wait long enough for the
    # evaluation to finish.
    before do
      @spec_fiber = Fiber.current
      await_scheduled_resume!
    end

    it { is_expected.to eq [:arg1, :arg2] }
  end

  context "when starting/resuming the fiber raises an error" do
    subject { call{}; wait 0 }
    let(:fiber_pool) { [] }
    let!(:fiber) { Concurrently::Proc::Fiber.new(fiber_pool) }
    before { allow(fiber).to receive(:resume_from_event_loop!).and_raise(FiberError, 'resume error') }
    before { allow(Concurrently::Proc::Fiber).to receive(:new).and_return(fiber) }
    before { allow(Concurrently::EventLoop.current).to receive(:proc_fiber_pool).and_return(fiber_pool) }

    it { is_expected.to raise_error(Concurrently::Error, "Event loop teared down (FiberError: resume error)") }

    # recover from the teared down event loop caused by the error for further
    # tests
    after { Concurrently::EventLoop.current.reinitialize! }
  end

  context "when the code inside the block raises an error" do
    subject { call{ raise Exception, 'error' }; wait 0 }

    before { expect_any_instance_of(Concurrently::Proc).to receive(:trigger).with(:error,
      (be_a(Exception).and have_attributes message: 'error')) }
    it { is_expected.not_to raise_error }
  end

  describe "the reuse of proc fibers" do
    subject { @fiber3 }

    let!(:evaluation1) { concurrent_proc{ @fiber1 = Fiber.current }.call_detached! }
    let!(:evaluation2) { concurrent_proc{ @fiber2 = Fiber.current }.call_detached }
    before { evaluation2.await_result } # let the two blocks finish
    let!(:evaluation3) { call do
      @fiber3 = Fiber.current
      @spec_fiber.schedule_resume!
    end }

    # We need a reference wait to ensure we wait long enough for the
    # evaluation to finish.
    before do
      @spec_fiber = Fiber.current
      await_scheduled_resume!
    end

    it { is_expected.to be @fiber2 }
    after { expect(subject).not_to be @fiber1 }
  end
end

shared_examples_for "#schedule_resume!" do
  before { concurrent_proc do
    wait 0.0001
    call *result
  end.call_detached }

  context "when given no result" do
    let(:result) { [] }
    it { is_expected.to eq nil }
  end

  context "when given a result" do
    let(:result) { :result }
    it { is_expected.to eq :result }
  end
end