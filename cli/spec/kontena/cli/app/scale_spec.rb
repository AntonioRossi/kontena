require_relative "../../../spec_helper"
require "kontena/cli/apps/scale_command"

describe Kontena::Cli::Apps::ScaleCommand do

  let(:subject) do
    described_class.new(File.basename($0))
  end

  let(:settings) do
    {'current_server' => 'alias',
     'servers' => [
         {'name' => 'some_master', 'url' => 'some_master'},
         {'name' => 'alias', 'url' => 'someurl', 'token' => token}
     ]
    }
  end

  let(:token) do
    '1234567'
  end

  let(:kontena_yml) do
    yml_content = <<yml
wordpress:
  image: wordpress:latest
  instances: 2
yml
  end

  let(:kontena_yml_no_instances) do
    yml_content = <<yml
wordpress:
  image: wordpress:latest
yml
  end

  describe '#execute' do
    before(:each) do
      allow(subject).to receive(:settings).and_return(settings)
      allow(subject).to receive(:current_dir).and_return("kontena-test")
      allow(File).to receive(:exists?).and_return(true)
      allow(File).to receive(:read).with("#{Dir.getwd}/kontena.yml").and_return(kontena_yml)
    end

    context 'when service already contains instances property' do
      it 'aborts execution' do
        expect{
          subject.run(['wordpress', 3])
        }.to raise_error(SystemExit)
      end
    end

    context 'when service not found in YML' do
      it 'aborts execution' do
        expect{
          subject.run(['mysql', 3])
        }.to raise_error(SystemExit)
      end
    end

    it 'scales given service' do
      allow(File).to receive(:read).with("#{Dir.getwd}/kontena.yml").and_return(kontena_yml_no_instances)
      expect(subject).to receive(:scale_service).with('1234567','kontena-test-wordpress',3)
      subject.run(['wordpress', 3])
    end

  end
end
