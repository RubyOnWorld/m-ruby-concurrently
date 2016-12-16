describe IOEventLoop do
  subject(:instance) { IOEventLoop.new }

  it { is_expected.to be_a FiberedEventLoop }

  describe "#start" do
    subject { instance.start }

    context "when it has no timers and nothing to watch" do
      before { expect(instance).to receive(:stop).and_call_original }
      it { is_expected.to be nil }
    end

    context "when it has nothing to watch but a timer to wait for" do
      before { instance.timers.after(0.01, &callback) }
      let(:callback) { proc{} }
      before { expect(callback).to receive(:call) }

      before { expect(instance).to receive(:stop).and_call_original }
      it { is_expected.to be nil }
    end

    context "when it has an IO object waiting for a single event" do
      let(:pipe) { IO.pipe }
      let(:reader) { pipe[0] }
      let(:writer) { pipe[1] }

      context "when its waiting to be readable" do
        before { instance.timers.after(0.01) { writer.write 'Wake up!'; writer.close } }
        before { instance.wait_for_readable(reader) }

        it { is_expected.to be nil }
        after { expect(reader.read).to eq 'Wake up!' }
      end

      context "when its waiting to be writable" do
        before { instance.wait_for_writable(writer) }

        it { is_expected.to be nil }
        after do
          writer.write 'Hello!'; writer.close
          expect(reader.read).to eq 'Hello!'
        end
      end
    end
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
      before { instance.timers.after(0.01) { writer.write 'Message!' } }

      context "when running the loop" do
        before { expect(callback1).to receive(:call).and_call_original }
        it { is_expected.to be nil }
      end

      context "when watching the same IO for a second time" do
        before { instance.attach_reader(reader, &callback2) }
        let(:callback2) { proc{ instance.detach_reader(reader) } }

        before { expect(callback2).to receive(:call).and_call_original.ordered }
        before { expect(callback1).to receive(:call).and_call_original.ordered }
        it { is_expected.to be nil }
      end
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

      context "when running the loop" do
        before { expect(callback1).to receive(:call).and_call_original }
        it { is_expected.to be nil }
      end

      context "when watching the same IO for a second time" do
        before { instance.attach_writer(writer, &callback2) }
        let(:callback2) { proc{ instance.detach_writer(writer) } }

        before { expect(callback2).to receive(:call).and_call_original.ordered }
        before { expect(callback1).to receive(:call).and_call_original.ordered }
        it { is_expected.to be nil }
      end
    end
  end

  describe "#wait_for_result with timeout" do
    subject { instance.wait_for_result(:id, 0.02) { raise "Time's up!" } }

    context "when the result arrives in time" do
      before { instance.timers.after(0.01) { instance.hand_result_to(:id, :result) } }
      it { is_expected.to be :result }
    end

    context "when evaluation of result is too slow" do
      it { is_expected.to raise_error "Time's up!" }
    end
  end

  describe "#wait_for_readable" do
    subject { instance.wait_for_readable(reader, *timeout, &timeout_callback) }

    let(:pipe) { IO.pipe }
    let(:reader) { pipe[0] }
    let(:writer) { pipe[1] }

    let(:timeout) { nil }
    let(:timeout_callback) { nil }

    context "when it has a timeout" do
      let(:timeout) { 0.02 }
      let(:timeout_callback) { proc{ raise "Time's up!" } }

      context "when readable in time" do
        before { instance.timers.after(0.01) { writer.write 'Wake up!' } }
        it { is_expected.to be :readable }
      end

      context "when not readable in time" do
        it { is_expected.to raise_error "Time's up!" }
      end
    end
  end

  describe "#wait_for_writable" do
    subject { instance.wait_for_writable(writer, *timeout, &timeout_callback) }

    let(:pipe) { IO.pipe }
    let(:reader) { pipe[0] }
    let(:writer) { pipe[1] }

    let(:timeout) { nil }
    let(:timeout_callback) { nil }

    context "when it has a timeout" do
      let(:timeout) { 0.02 }
      let(:timeout_callback) { proc{ raise "Time's up!" } }

      # jam pipe: default pipe buffer size on linux is 65536
      before { writer.write('a' * 65536) }

      context "when writable in time" do
        before { instance.timers.after(0.01) { reader.read(65536) } } # clear the pipe
        it { is_expected.to be :writable }
      end

      context "when not writable in time" do
        it { is_expected.to raise_error "Time's up!" }
      end
    end
  end
end