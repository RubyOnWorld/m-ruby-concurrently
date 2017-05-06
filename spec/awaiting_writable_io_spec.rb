describe "using #await_writable in concurrent blocks" do
  let(:loop) { IOEventLoop.new }

  let(:pipe) { IO.pipe }
  let(:reader) { pipe[0] }
  let(:writer) { pipe[1] }

  # jam pipe: default pipe buffer size on linux is 65536
  before { writer.write('a' * 65536) }

  describe "waiting indefinitely" do
    subject { concurrency.result }

    before { loop.concurrently do
      loop.wait 0.0001
      reader.read 65536 # clears the pipe
    end }

    let(:wait_proc) { proc do
      loop.await_writable writer
      writer.write 'test'
    end }

    context "when originating inside a concurrent block" do
      subject { loop.concurrently(&wait_proc).result }
      it { is_expected.to be 4 }
    end

    context "when originating outside a concurrent block" do
      subject { wait_proc.call }
      it { is_expected.to be 4 }
    end
  end

  describe "waiting with a timeout" do
    subject { concurrency.result }

    let(:concurrency) { loop.concurrently do
      loop.await_writable writer, within: 0.0005
    end }

    context "when writable after some time" do
      before { loop.concurrently do
        loop.wait(0.0001)
        reader.read(65536) # clears the pipe
      end }

      it { is_expected.to be true }
    end

    context "when not writable in time" do
      it { is_expected.to be false }
    end
  end
end