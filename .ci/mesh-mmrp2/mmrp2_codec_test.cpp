#include "mmrp2_codec.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

using mesh::mmrp2::FrameClass;
using mesh::mmrp2::Fragment;
using mesh::mmrp2::Header;
using mesh::mmrp2::LinkAck;
using mesh::mmrp2::TrafficClass;

std::string Hex(const std::vector<std::uint8_t>& bytes) {
  std::ostringstream out;
  out << std::hex << std::setfill('0');
  for (const auto byte : bytes) {
    out << std::setw(2) << static_cast<int>(byte);
  }
  return out.str();
}

template <std::size_t N>
std::string Hex(const std::array<std::uint8_t, N>& bytes) {
  return Hex(std::vector<std::uint8_t>(bytes.begin(), bytes.end()));
}

std::array<std::uint8_t, 8> RouteTag(
    std::initializer_list<std::uint8_t> values) {
  if (values.size() != 8) throw std::runtime_error("route tag length");
  std::array<std::uint8_t, 8> out{};
  std::copy(values.begin(), values.end(), out.begin());
  return out;
}

void Check(bool condition, const char* label) {
  if (!condition) throw std::runtime_error(label);
}

template <typename Fn>
void ExpectReject(Fn fn, const char* label) {
  bool rejected = false;
  try {
    fn();
  } catch (const std::invalid_argument&) {
    rejected = true;
  }
  Check(rejected, label);
}

}  // namespace

int main() {
  using namespace mesh::mmrp2;

  Header a{};
  a.frame_class = FrameClass::kData;
  a.traffic_class = TrafficClass::kInteractive;
  a.hop_limit = 3;
  a.ttl_class = 0;
  a.route_tag = RouteTag({0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88});
  a.packet_counter = 0x01020304;
  Check(Hex(EncodeHeader(a)) == "24000130112233445566778801020304",
        "vector A");

  Header b{};
  b.flags = kFlagHopAead;
  b.frame_class = FrameClass::kData;
  b.traffic_class = TrafficClass::kInteractive;
  b.hop_limit = 1;
  b.ttl_class = 1;
  b.route_tag = RouteTag({0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11});
  b.packet_counter = 42;
  Check(Hex(EncodeHeader(b)) == "2404011188776655443322110000002a",
        "vector B");

  Packet b_packet{};
  b_packet.header = b;
  b_packet.payload = {0xde, 0xad, 0xbe, 0xef};
  b_packet.hop_aead_tag =
      {0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
       0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f};
  const auto b_encoded = EncodePacket(b_packet);
  const auto b_decoded = DecodePacket(b_encoded);
  Check(Hex(b_decoded.payload) == "deadbeef", "vector B payload");
  Check(Hex(b_decoded.hop_aead_tag) ==
            "000102030405060708090a0b0c0d0e0f",
        "vector B tag");
  ExpectReject([&]() { EncodePacket(Packet{b, {0x01}, {}}); },
               "missing HOP_AEAD tag");
  ExpectReject([&]() { DecodePacket(b_encoded, b_encoded.size() - 1); },
               "max frame bound");
  ExpectReject([&]() { DecodePacket(b_encoded, 65535, 3); },
               "max payload bound");

  Header c{};
  c.flags = static_cast<std::uint8_t>(kFlagFragmented | kFlagHopAead);
  c.frame_class = FrameClass::kData;
  c.traffic_class = TrafficClass::kBulk;
  c.hop_limit = 2;
  c.ttl_class = 2;
  c.route_tag = RouteTag({0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08});
  c.packet_counter = 16;
  c.fragmented = true;
  c.fragment = Fragment{0xa1b2c3d4, 1, 3};
  Check(
      Hex(EncodeHeader(c)) ==
          "26060222010203040506070800000010a1b2c3d400010003",
      "vector C");

  Header d{};
  d.flags = kFlagHopAead;
  d.frame_class = FrameClass::kLinkAck;
  d.traffic_class = TrafficClass::kUrgentControl;
  d.hop_limit = 1;
  d.ttl_class = 0;
  d.route_tag = RouteTag({0x0f, 0x0e, 0x0d, 0x0c, 0x0b, 0x0a, 0x09, 0x08});
  d.packet_counter = 32;
  Check(Hex(EncodeHeader(d)) == "240410100f0e0d0c0b0a090800000020",
        "vector D header");
  Check(Hex(EncodeLinkAckBody(LinkAck{31, 7})) == "0000001f00000007",
        "vector D ACK");

  auto n1 = EncodeHeader(a);
  n1[0] = 0x23;
  ExpectReject([&]() { DecodeHeader(n1); }, "N1");

  auto n2 = EncodeHeader(a);
  n2[1] = 0x80;
  ExpectReject([&]() { DecodeHeader(n2); }, "N2");

  auto n3 = EncodeHeader(a);
  for (std::size_t i = 4; i < 12; ++i) n3[i] = 0;
  ExpectReject([&]() { DecodeHeader(n3); }, "N3");

  auto n4 = EncodeHeader(a);
  n4[1] = kFlagFragmented;
  ExpectReject([&]() { DecodeHeader(n4); }, "N4");

  auto n5 = EncodeHeader(c);
  n5[22] = 0;
  n5[23] = 1;
  ExpectReject([&]() { DecodeHeader(n5); }, "N5");

  ReplayWindow replay;
  Check(replay.Accept(100), "N6 first");
  Check(!replay.Accept(100), "N6 duplicate");
  Check(replay.Accept(102), "N6 forward");
  Check(replay.Accept(101), "N6 out of order");
  Check(!replay.Accept(101), "N6 duplicate out of order");
  Check(replay.Accept(200), "N6 large advance");
  Check(!replay.Accept(100), "N6 too old");
  replay.ResetForNewSecurityEpoch();
  Check(replay.Accept(100), "N6 reset");

  std::cout << "MMRP2_CPP_GOLDEN_VECTOR_PASS\n";
  return 0;
}
