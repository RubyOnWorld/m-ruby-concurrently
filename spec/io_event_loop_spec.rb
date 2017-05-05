describe IOEventLoop do
  subject(:instance) { IOEventLoop.new }

  describe "#start" do
    subject { instance.start }

    before { instance.concurrently{ expect(instance).to be_running } }
    after { expect(instance).not_to be_running }

    context "when it has no timers and nothing to watch" do
      it { is_expected.to be nil }
    end

    context "when it has nothing to watch but a timer to wait for" do
      before { instance.concurrently do
        instance.now_in(0.0001).await
        callback.call
      end }
      let(:callback) { proc{} }
      before { expect(callback).to receive(:call) }

      it { is_expected.to be nil }
    end

    context "when it has an IO object waiting for a single event" do
      let(:pipe) { IO.pipe }
      let(:reader) { pipe[0] }
      let(:writer) { pipe[1] }

      context "when its waiting to be readable" do
        before { instance.concurrently do
          instance.readable(reader).await
          @result = reader.read
        end }

        before { instance.concurrently do
          instance.now_in(0.0001).await
          writer.write 'Wake up!'
          writer.close
        end }

        it { is_expected.to be nil }
        after { expect(@result).to eq 'Wake up!' }
      end

      context "when its waiting to be writable" do
        # jam pipe: default pipe buffer size on linux is 65536
        before { writer.write('a' * 65536) }

        before { instance.concurrently do
          instance.writable(writer).await
          @result = writer.write 'Hello!'
        end }

        before { instance.concurrently do
          instance.now_in(0.0001).await
          reader.read(65536) # clears the pipe
        end }

        it { is_expected.to be nil }
        after { expect(@result).to eq 6 }
      end
    end
  end

  describe "an iteration causing an error" do
    subject { instance.start }
    before { instance.concurrently{ raise 'evil error' }  }

    before { expect(instance).to receive(:trigger).with(:error,
      (be_a(RuntimeError).and have_attributes message: 'evil error')).and_call_original }

    context "when the loop should stop and raise the error (the default)" do
      it { is_expected.to raise_error 'evil error' }
    end

    context "when the loop should forgive the error" do
      before { instance.forgive_iteration_errors! }
      it { is_expected.to be nil }
    end
  end

  describe "#after" do
    subject { instance.start }

    let(:timer1) { instance.now_in(seconds1) }
    let(:timer2) { instance.now_in(seconds2) }
    let(:timer3) { instance.now_in(seconds3) }

    before { instance.concurrently{ (timer1.await; callback1.call) rescue nil } }
    before { instance.concurrently{ (timer2.await; callback2.call) rescue nil } }
    before { instance.concurrently{ (timer3.await; callback3.call) rescue nil } }
    let(:seconds1) { 0.0001 }
    let(:seconds2) { 0.0003 }
    let(:seconds3) { 0.0002 }
    let(:callback1) { proc{} }
    let(:callback2) { proc{} }
    let(:callback3) { proc{} }

    context "when no timer has been cancelled" do
      before { expect(callback1).to receive(:call).ordered }
      before { expect(callback3).to receive(:call).ordered }
      before { expect(callback2).to receive(:call).ordered }

      it { is_expected.not_to raise_error }
    end

    context "when the first timer has been cancelled" do
      before { timer1.cancel }

      before { expect(callback1).not_to receive(:call) }
      before { expect(callback3).to receive(:call).ordered }
      before { expect(callback2).to receive(:call).ordered }
      it { is_expected.not_to raise_error }
    end

    context "when the first and second timer have been cancelled" do
      before { timer1.cancel }
      before { timer3.cancel }

      before { expect(callback1).not_to receive(:call) }
      before { expect(callback3).not_to receive(:call) }
      before { expect(callback2).to receive(:call).ordered }
      it { is_expected.not_to raise_error }
    end

    context "when all timers have been cancelled" do
      before { timer1.cancel }
      before { timer3.cancel }
      before { timer2.cancel }

      before { expect(callback1).not_to receive(:call) }
      before { expect(callback3).not_to receive(:call) }
      before { expect(callback2).not_to receive(:call) }
      it { is_expected.not_to raise_error }
    end

    context "when the second timer has been cancelled" do
      before { timer3.cancel }

      before { expect(callback1).to receive(:call).ordered }
      before { expect(callback3).not_to receive(:call) }
      before { expect(callback2).to receive(:call).ordered }
      it { is_expected.not_to raise_error }
    end

    context "when the second and last timer have been cancelled" do
      before { timer3.cancel }
      before { timer2.cancel }

      before { expect(callback1).to receive(:call).ordered }
      before { expect(callback3).not_to receive(:call) }
      before { expect(callback2).not_to receive(:call) }
      it { is_expected.not_to raise_error }
    end

    context "when a timer cancels a timer coming afterwards in the same batch" do
      let(:seconds1) { 0 }
      let(:seconds2) { 0.0001 }
      let(:seconds3) { 0 }
      let(:callback1) { proc{ timer3.cancel } }

      before { expect(callback1).to receive(:call).and_call_original }
      before { expect(callback3).not_to receive(:call) }
      it { is_expected.not_to raise_error }
    end

    context "when all timers are triggered in one go" do
      let(:seconds1) { 0 }
      let(:seconds2) { 0 }
      let(:seconds3) { 0 }

      before { expect(callback1).to receive(:call).ordered }
      before { expect(callback2).to receive(:call).ordered }
      before { expect(callback3).to receive(:call).ordered }
      it { is_expected.not_to raise_error }
    end
  end

  describe "repeated execution in a fixed interval" do
    subject { instance.start }

    before { @count = 0 }
    before { instance.concurrently do
      while (@count += 1) < 4
        instance.now_in(0.0001).await
        callback.call
      end
    end }
    let(:callback) { proc{} }

    before { expect(callback).to receive(:call).exactly(3).times }
    it { is_expected.not_to raise_error }
  end

  describe "#attach_reader and #detach_reader" do
    subject { instance.start }

    let(:pipe) { IO.pipe }
    let(:reader) { pipe[0] }
    let(:writer) { pipe[1] }

    context "when watching readability" do
      before { instance.attach_reader(reader, &callback1) }
      let(:callback1) { proc{ instance.detach_reader(reader) } }

      # make the reader readable
      before { instance.concurrently do
        instance.now_in(0.0001).await
        writer.write 'Message!'
      end }

      before { expect(callback1).to receive(:call).and_call_original }
      it { is_expected.to be nil }
    end
  end

  describe "#attach_writer and #detach_writer" do
    subject { instance.start }

    let(:pipe) { IO.pipe }
    let(:reader) { pipe[0] }
    let(:writer) { pipe[1] }

    context "when watching writability" do
      before { instance.attach_writer(writer, &callback1) }
      let(:callback1) { proc{ instance.detach_writer(writer) } }

      before { expect(callback1).to receive(:call).and_call_original }
      it { is_expected.to be nil }
    end
  end

  describe "#watch_events" do
    subject { instance.watch_events(object, :event) }

    let(:object) { Object.new.extend CallbacksAttachable }

    it { is_expected.to be_a(IOEventLoop::EventWatcher).and having_attributes(loop: instance,
      subject: object, event: :event)}
  end
end