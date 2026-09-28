#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <vector>

namespace mesh::mmrp2 {

constexpr std::uint8_t kVersion = 2;
constexpr std::size_t kBaseHeaderBytes = 16;
constexpr std::size_t kFragmentExtensionBytes = 8;
constexpr std::size_t kHopAeadTagBytes = 16;
constexpr std::size_t kLinkAckBodyBytes = 8;

constexpr std::uint8_t kFlagAckRequested = 0x01;
constexpr std::uint8_t kFlagFragmented = 0x02;
constexpr std::uint8_t kFlagHopAead = 0x04;
constexpr std::uint8_t kFlagStoreForwardEligible = 0x08;
constexpr std::uint8_t kFlagPadded = 0x10;
constexpr std::uint8_t kFlagRotateTagHint = 0x20;

enum class FrameClass : std::uint8_t {
  kData = 0,
  kLinkAck = 1,
  kControl = 2,
  kDiscovery = 3,
  kCapability = 4,
  kKeepalivePadding = 5,
  kExtension = 15,
};

enum class TrafficClass : std::uint8_t {
  kUrgentControl = 0,
  kInteractive = 1,
  kBulk = 2,
  kBackground = 3,
};

struct Fragment {
  std::uint32_t fragment_group_id{};
  std::uint16_t fragment_index{};
  std::uint16_t fragment_count{};
};

struct Header {
  std::uint8_t flags{};
  FrameClass frame_class{FrameClass::kData};
  TrafficClass traffic_class{TrafficClass::kInteractive};
  std::uint8_t hop_limit{};
  std::uint8_t ttl_class{};
  std::array<std::uint8_t, 8> route_tag{};
  std::uint32_t packet_counter{};
  bool fragmented{};
  Fragment fragment{};
};

struct LinkAck {
  std::uint32_t ack_base_counter{};
  std::uint32_t ack_bitmap{};
};

std::vector<std::uint8_t> EncodeHeader(const Header& header);
Header DecodeHeader(const std::vector<std::uint8_t>& bytes);
std::array<std::uint8_t, kLinkAckBodyBytes> EncodeLinkAckBody(const LinkAck& ack);
LinkAck DecodeLinkAckBody(const std::vector<std::uint8_t>& bytes);

class ReplayWindow {
 public:
  bool Accept(std::uint32_t counter);
  void ResetForNewSecurityEpoch();

 private:
  bool initialized_{false};
  std::uint32_t highest_{0};
  std::uint64_t bitmap_{0};
};

}  // namespace mesh::mmrp2
