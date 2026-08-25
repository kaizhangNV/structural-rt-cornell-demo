#pragma once

#include <cstdint>
#include <fstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

struct ReflectedHitGroup
{
    uint32_t slot = 0;
    std::string groupName;
    std::string closestHit;
    std::string anyHit;
    std::string intersection;
};

struct ReflectedMissGroup
{
    uint32_t slot = 0;
    std::string groupName;
    std::string miss;
};

struct ReflectedCallableGroup
{
    uint32_t slot = 0;
    std::string groupName;
    std::string callable;
};

struct ReflectedProgramLayout
{
    std::vector<ReflectedHitGroup> hitGroups;
    std::vector<ReflectedMissGroup> missGroups;
    std::vector<ReflectedCallableGroup> callableGroups;
};

// Places a group at its reflected shader-table index and rejects ambiguous
// layouts.
template<typename T>
inline void placeReflectedGroup(std::vector<T>& groups, int64_t slot, T group)
{
    if (slot < 0)
        throw std::runtime_error("a reflected shader-group slot is negative");
    if (groups.size() <= size_t(slot))
        groups.resize(size_t(slot) + 1);
    if (!groups[size_t(slot)].groupName.empty())
        throw std::runtime_error("two reflected shader groups use the same slot");
    groups[size_t(slot)] = std::move(group);
}

inline std::string encodeStageName(const std::string& name)
{
    return name.empty() ? "-" : name;
}

inline std::string decodeStageName(const std::string& name)
{
    return name == "-" ? std::string() : name;
}

inline void writeReflectedProgramLayout(const char* path, const ReflectedProgramLayout& layout)
{
    std::ofstream stream(path);
    if (!stream)
        throw std::runtime_error(std::string("write reflected program layout: ") + path);
    stream << "structural-ray-tracing-layout 1\n";
    for (const auto& group : layout.hitGroups)
    {
        if (group.groupName.empty())
            continue;
        stream << "hit " << group.slot << " " << group.groupName << " "
               << encodeStageName(group.closestHit) << " " << encodeStageName(group.anyHit) << " "
               << encodeStageName(group.intersection) << "\n";
    }
    for (const auto& group : layout.missGroups)
    {
        if (group.groupName.empty())
            continue;
        stream << "miss " << group.slot << " " << group.groupName << " " << group.miss << "\n";
    }
    for (const auto& group : layout.callableGroups)
    {
        if (group.groupName.empty())
            continue;
        stream << "callable " << group.slot << " " << group.groupName << " " << group.callable
               << "\n";
    }
}

inline ReflectedProgramLayout readReflectedProgramLayout(const char* path)
{
    std::ifstream stream(path);
    if (!stream)
        throw std::runtime_error(std::string("read reflected program layout: ") + path);
    std::string magic;
    uint32_t version = 0;
    stream >> magic >> version;
    if (magic != "structural-ray-tracing-layout" || version != 1)
        throw std::runtime_error("unsupported structural ray-tracing layout manifest");

    ReflectedProgramLayout result;
    std::string kind;
    while (stream >> kind)
    {
        if (kind == "hit")
        {
            ReflectedHitGroup group;
            if (!(stream >> group.slot >> group.groupName >> group.closestHit >> group.anyHit >>
                  group.intersection))
                throw std::runtime_error("invalid reflected hit-group record");
            group.closestHit = decodeStageName(group.closestHit);
            group.anyHit = decodeStageName(group.anyHit);
            group.intersection = decodeStageName(group.intersection);
            placeReflectedGroup(result.hitGroups, group.slot, std::move(group));
        }
        else if (kind == "miss")
        {
            ReflectedMissGroup group;
            if (!(stream >> group.slot >> group.groupName >> group.miss))
                throw std::runtime_error("invalid reflected miss-group record");
            placeReflectedGroup(result.missGroups, group.slot, std::move(group));
        }
        else if (kind == "callable")
        {
            ReflectedCallableGroup group;
            if (!(stream >> group.slot >> group.groupName >> group.callable))
                throw std::runtime_error("invalid reflected callable-group record");
            placeReflectedGroup(result.callableGroups, group.slot, std::move(group));
        }
        else
        {
            throw std::runtime_error("invalid structural ray-tracing layout manifest");
        }
    }
    return result;
}
