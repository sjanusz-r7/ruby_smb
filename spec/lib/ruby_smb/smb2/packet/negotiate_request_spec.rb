require 'spec_helper'

RSpec.describe RubySMB::SMB2::Packet::NegotiateRequest do
  subject(:packet) do
    described_class.new(data)
  end

  context 'with packet bytes' do
    let(:data) do
      [
        "fe534d42400001000000000000001f0000000000000000000000000000000000" \
        "fffe000000000000000000000000000000000000000000000000000000000000" \
        "24000300010000007f000000ec1cb173f176e411af9e000c293f25dc00000000" \
        "00000000020210020003"
      ].pack('H*')
    end

    it_behaves_like 'packet'
    it_behaves_like 'request', RubySMB::SMB2::COMMANDS[:NEGOTIATE]
    it_behaves_like 'smb2_negotiate_packet_header'

    context 'body' do
      specify do
        expect(packet.struct_size).to eq(36)
      end
      specify do
        expect(packet.dialect_count).to eq(3)
      end
      specify do
        expect(packet.security_mode).to eq(1)
      end
      specify do
        expect(packet.reserved).to eq(0)
      end
      specify do
        # TODO constantize
        expect(packet.capabilities).to eq(127)
      end

      specify do
        expect(packet.client_guid).to eq(["ec1cb173f176e411af9e000c293f25dc"].pack("H*"))
      end

      specify do
        expect(packet.dialects).to eq(["020210020003"].pack("H*"))
      end

    end

  end
end
