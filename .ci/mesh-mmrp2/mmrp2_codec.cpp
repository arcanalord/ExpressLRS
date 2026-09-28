#include "mmrp2_codec.hpp"

#include <algorithm>

namespace mesh::mmrp2 {
namespace {

constexpr std::uint8_t kAllowedFlags = 0x3f;
constexpr std::uint8_t kReservedFlags = 0xc0;

void WriteU16(std::vector<std::uint8_t>& out, std::size_t offset,
              std::uint16_t value) {
  out.at(offset) = static_cast<std::uint8_t>((value >> 8) & 0xff);
  out.at(offset + 1) = static_cast<std::uint8_t>(value & 0xff);
}

void WriteU32(std::vector<std::uint8_t>& out, std::size_t offset,
              std::uint32_t value) {
  out.at(offset) = static_cast<std::uint8_t>((value >> 24) & 0xff);
  out.at(offset + 1) = static_cast<std::uint8_t>((value >> 16) & 0xff);
  out.at(offset + 2) = static_cast<std::uint8_t>((value >> 8) & 0xff);
  out.at(offset + 3) = static_cast<std::uint8_t>(value & 0xff);
}

std::uint16_t ReadU16(const std::vector<std::uint8_t>& bytes,
                      std::size_t offset) {
  return static_cast<std::uint16_t>(
      (static_cast<std::uint16_t>(bytes.at(offset)) << 8) |
      static_cast<std::uint16_t>(bytes.at(offset + 1)));
}

std::uint32_t ReadU32(const std::vector<std::uint8_t>& bytes,
                      std::size_t offset) {
  return (static_cast<std::uint32_t>(bytes.at(offset)) << 24) |
         (static_cast<std::uint32_t>(bytes.at(offset + 1)) << 16) |
         (static_cast<std::uint32_t>(bytes.at(offset + 2)) << 8) |
         static_cast<std::uint32_t>(bytes.at(offset + 3));
}

bool AllZero(const std::array<std::uint8_t, 8>& tag) {
  return std::all_of(tag.begin(), tag.end(),
                     [](std::uint8_t value) { return value == 0; });
}

FrameClass ParseFrameClass(std::uint8_t value) {
  switch (value) {
    case 0:
      return FrameClass::kData;
    case 1:
      return FrameClass::kLinkAck;
    case 2:
      return FrameClass::kControl;
    case 3:
      return FrameClass::kDiscovery;
    case 4:
      return FrameClass::kCapability;
    case 5:
      return FrameClass::kKeepalivePadding;
    case 15:
      return FrameClass::kExtension;
    default:
      throw std::invalid_argument("Reserved/unknown MMRP/2 frame class");
  }
}

TrafficClass ParseTrafficClass(std::uint8_t value) {
  switch (value) {
    case 0:
      return TrafficClass::kUrgentControl;
    case 1:
      return TrafficClass::kInteractive;
    case 2:
      return TrafficClass::kBulk;
    case 3:
      return TrafficClass::kBackground;
    default:
      throw std::invalid_argument("Reserved/unknown MMRP/2 traffic class");
  }
}

void ValidateFragment(const Fragment& fragment) {
  if (fragment.fragment_count < 2 ||
      fragment.fragment_index >= fragment.fragment_count) {
    throw std::invalid_argument("Invalid MMRP/2 fragment metadata");
  }
}

void ValidateHeader(const Header& header) {
  if ((header.flags & kAllowedFlags) != header.flags ||
      (header.flags & kReservedFlags) != 0) {
    throw std::invalid_argument("Reserved MMRP/2 flag bits are set");
  }
  if (header.hop_limit > 15 || header.ttl_class > 7) {
    throw std::invalid_argument("Invalid MMRP/2 hop_limit/ttl_class");
  }
  const bool flag_fragmented = (header.flags & kFlagFragmented) != 0;
  if (flag_fragmented != header.fragmented) {
    throw std::invalid_argument(
        "FRAGMENTED flag and fragment extension must agree");
  }
  if (header.fragmented) {
    ValidateFragment(header.fragment);
  }
  if (AllZero(header.route_tag) &&
      header.frame_class != FrameClass::kDiscovery &&
      header.frame_class != FrameClass::kCapability) {
    throw std::invalid_argument(
        "route_tag=0 is only valid for broadcast discovery/capability");
  }
}

}  // namespace

std::vector<std::uint8_t> EncodeHeader(const Header& header) {
  ValidateHeader(header);
  const std::size_t header_bytes =
      header.fragmented ? kBaseHeaderBytes + kFragmentExtensionBytes
                        : kBaseHeaderBytes;
  const std::uint8_t header_words =
      static_cast<std::uint8_t>(header_bytes / 4);
  std::vector<std::uint8_t> out(header_bytes, 0);

  out[0] = static_cast<std::uint8_t>((kVersion << 4) | header_words);
  out[1] = header.flags;
  out[2] = static_cast<std::uint8_t>(
      (static_cast<std::uint8_t>(header.frame_class) << 4) |
      static_cast<std::uint8_t>(header.traffic_class));
  out[3] =
      static_cast<std::uint8_t>((header.hop_limit << 4) | header.ttl_class);
  std::copy(header.route_tag.begin(), header.route_tag.end(), out.begin() + 4);
  WriteU32(out, 12, header.packet_counter);

  if (header.fragmented) {
    WriteU32(out, 16, header.fragment.fragment_group_id);
    WriteU16(out, 20, header.fragment.fragment_index);
    WriteU16(out, 22, header.fragment.fragment_count);
  }

  return out;
}

Header DecodeHeader(const std::vector<std::uint8_t>& bytes) {
  if (bytes.size() < kBaseHeaderBytes) {
    throw std::invalid_argument("MMRP/2 frame shorter than base header");
  }

  const std::uint8_t first = bytes[0];
  const std::uint8_t version = static_cast<std::uint8_t>(first >> 4);
  const std::uint8_t header_words = static_cast<std::uint8_t>(first & 0x0f);
  if (version != kVersion) {
    throw std::invalid_argument("Unsupported MMRP version");
  }
  if (header_words < 4 || header_words > 15) {
    throw std::invalid_argument("Invalid MMRP/2 header_words");
  }

  const std::size_t header_bytes = static_cast<std::size_t>(header_words) * 4;
  if (header_bytes > bytes.size()) {
    throw std::invalid_argument("Truncated MMRP/2 header");
  }

  const std::uint8_t flags = bytes[1];
  if ((flags & kReservedFlags) != 0) {
    throw std::invalid_argument("Reserved MMRP/2 flag bits are set");
  }

  const bool fragmented = (flags & kFlagFragmented) != 0;
  const std::size_t expected_header_bytes =
      fragmented ? kBaseHeaderBytes + kFragmentExtensionBytes
                 : kBaseHeaderBytes;
  if (header_bytes != expected_header_bytes) {
    throw std::invalid_argument("Unknown or malformed MMRP/2 header extension");
  }

  Header header{};
  header.flags = flags;
  header.frame_class = ParseFrameClass(static_cast<std::uint8_t>(bytes[2] >> 4));
  header.traffic_class =
      ParseTrafficClass(static_cast<std::uint8_t>(bytes[2] & 0x0f));
  header.hop_limit = static_cast<std::uint8_t>(bytes[3] >> 4);
  header.ttl_class = static_cast<std::uint8_t>(bytes[3] & 0x0f);
  if (header.ttl_class > 7) {
    throw std::invalid_argument("Reserved MMRP/2 ttl_class");
  }

  std::copy(bytes.begin() + 4, bytes.begin() + 12, header.route_tag.begin());
  if (AllZero(header.route_tag) &&
      header.frame_class != FrameClass::kDiscovery &&
      header.frame_class != FrameClass::kCapability) {
    throw std::invalid_argument(
        "route_tag=0 is only valid for broadcast discovery/capability");
  }

  header.packet_counter = ReadU32(bytes, 12);
  header.fragmented = fragmented;
  if (fragmented) {
    header.fragment.fragment_group_id = ReadU32(bytes, 16);
    header.fragment.fragment_index = ReadU16(bytes, 20);
    header.fragment.fragment_count = ReadU16(bytes, 22);
    ValidateFragment(header.fragment);
  }

  return header;
}

std::vector<std::uint8_t> EncodePacket(const Packet& packet,
                                       std::size_t max_frame_bytes,
                                       std::size_t max_payload_bytes) {
  if (max_frame_bytes < kBaseHeaderBytes) {
    throw std::invalid_argument("max_frame_bytes too small");
  }
  if (packet.payload.size() > max_payload_bytes) {
    throw std::invalid_argument("MMRP/2 payload exceeds negotiated limit");
  }

  const auto header = EncodeHeader(packet.header);
  const bool hop_aead = (packet.header.flags & kFlagHopAead) != 0;
  if (hop_aead) {
    if (packet.hop_aead_tag.size() != kHopAeadTagBytes) {
      throw std::invalid_argument("HOP_AEAD requires an exact 16-byte tag");
    }
  } else if (!packet.hop_aead_tag.empty()) {
    throw std::invalid_argument("Hop AEAD tag present without HOP_AEAD flag");
  }

  const std::size_t total =
      header.size() + packet.payload.size() + packet.hop_aead_tag.size();
  if (total > max_frame_bytes) {
    throw std::invalid_argument("MMRP/2 frame exceeds negotiated max_frame_bytes");
  }

  std::vector<std::uint8_t> out;
  out.reserve(total);
  out.insert(out.end(), header.begin(), header.end());
  out.insert(out.end(), packet.payload.begin(), packet.payload.end());
  out.insert(out.end(), packet.hop_aead_tag.begin(), packet.hop_aead_tag.end());
  return out;
}

Packet DecodePacket(const std::vector<std::uint8_t>& bytes,
                    std::size_t max_frame_bytes,
                    std::size_t max_payload_bytes) {
  if (bytes.size() > max_frame_bytes) {
    throw std::invalid_argument("MMRP/2 frame exceeds negotiated max_frame_bytes");
  }

  Packet packet{};
  packet.header = DecodeHeader(bytes);
  const std::size_t header_bytes =
      packet.header.fragmented ? kBaseHeaderBytes + kFragmentExtensionBytes
                               : kBaseHeaderBytes;
  const bool hop_aead = (packet.header.flags & kFlagHopAead) != 0;
  const std::size_t tag_bytes = hop_aead ? kHopAeadTagBytes : 0;
  if (bytes.size() < header_bytes + tag_bytes) {
    throw std::invalid_argument("Truncated MMRP/2 frame/tag");
  }

  const std::size_t payload_end = bytes.size() - tag_bytes;
  packet.payload.assign(bytes.begin() + static_cast<std::ptrdiff_t>(header_bytes),
                        bytes.begin() + static_cast<std::ptrdiff_t>(payload_end));
  if (packet.payload.size() > max_payload_bytes) {
    throw std::invalid_argument("MMRP/2 payload exceeds negotiated limit");
  }
  if (packet.header.frame_class == FrameClass::kLinkAck &&
      packet.payload.size() != kLinkAckBodyBytes) {
    throw std::invalid_argument("LINK_ACK payload must be exactly 8 bytes");
  }
  if (hop_aead) {
    packet.hop_aead_tag.assign(
        bytes.begin() + static_cast<std::ptrdiff_t>(payload_end), bytes.end());
  }
  return packet;
}

std::array<std::uint8_t, kLinkAckBodyBytes> EncodeLinkAckBody(
    const LinkAck& ack) {
  std::vector<std::uint8_t> tmp(kLinkAckBodyBytes, 0);
  WriteU32(tmp, 0, ack.ack_base_counter);
  WriteU32(tmp, 4, ack.ack_bitmap);
  std::array<std::uint8_t, kLinkAckBodyBytes> out{};
  std::copy(tmp.begin(), tmp.end(), out.begin());
  return out;
}

LinkAck DecodeLinkAckBody(const std::vector<std::uint8_t>& bytes) {
  if (bytes.size() != kLinkAckBodyBytes) {
    throw std::invalid_argument("LINK_ACK body must be exactly 8 bytes");
  }
  return LinkAck{ReadU32(bytes, 0), ReadU32(bytes, 4)};
}

bool ReplayWindow::Accept(std::uint32_t counter) {
  if (!initialized_) {
    initialized_ = true;
    highest_ = counter;
    bitmap_ = 1;
    return true;
  }

  if (counter > highest_) {
    const std::uint64_t shift =
        static_cast<std::uint64_t>(counter) - static_cast<std::uint64_t>(highest_);
    bitmap_ = shift >= 64 ? 1 : static_cast<std::uint64_t>((bitmap_ << shift) | 1);
    highest_ = counter;
    return true;
  }

  const std::uint64_t delta =
      static_cast<std::uint64_t>(highest_) - static_cast<std::uint64_t>(counter);
  if (delta >= 64) {
    return false;
  }

  const std::uint64_t bit = static_cast<std::uint64_t>(1) << delta;
  if ((bitmap_ & bit) != 0) {
    return false;
  }
  bitmap_ |= bit;
  return true;
}

void ReplayWindow::ResetForNewSecurityEpoch() {
  initialized_ = false;
  highest_ = 0;
  bitmap_ = 0;
}

}  // namespace mesh::mmrp2
