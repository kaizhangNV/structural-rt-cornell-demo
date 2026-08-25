#pragma once

#include "program-layout.h"

#include <slang.h>

inline std::string
getReflectedStageName(slang::RayTracingStageReflection *stage) {
  return stage ? stage->getEntryPointName() : std::string();
}

// Converts Slang's structural reflection into arrays indexed by the declared
// group slots.
inline ReflectedProgramLayout
reflectProgramLayout(slang::ProgramLayout *program, const char *typeName) {
  auto reflection = program->findTraceProgramLayout(typeName);
  if (!reflection)
    throw std::runtime_error(std::string("reflect trace program layout: ") +
                             typeName);

  ReflectedProgramLayout result;
  for (SlangUInt i = 0; i < reflection->getHitGroupCount(); ++i) {
    auto reflectedGroup = reflection->getHitGroup(i);
    ReflectedHitGroup group = {
        uint32_t(reflectedGroup->getSlot()),
        reflectedGroup->getType()->getName(),
        getReflectedStageName(reflectedGroup->getClosestHit()),
        getReflectedStageName(reflectedGroup->getAnyHit()),
        getReflectedStageName(reflectedGroup->getIntersection()),
    };
    placeReflectedGroup(result.hitGroups, reflectedGroup->getSlot(),
                        std::move(group));
  }
  for (SlangUInt i = 0; i < reflection->getMissGroupCount(); ++i) {
    auto reflectedGroup = reflection->getMissGroup(i);
    ReflectedMissGroup group = {
        uint32_t(reflectedGroup->getSlot()),
        reflectedGroup->getType()->getName(),
        getReflectedStageName(reflectedGroup->getMiss()),
    };
    placeReflectedGroup(result.missGroups, reflectedGroup->getSlot(),
                        std::move(group));
  }
  for (SlangUInt i = 0; i < reflection->getCallableGroupCount(); ++i) {
    auto reflectedGroup = reflection->getCallableGroup(i);
    ReflectedCallableGroup group = {
        uint32_t(reflectedGroup->getSlot()),
        reflectedGroup->getType()->getName(),
        getReflectedStageName(reflectedGroup->getCallable()),
    };
    placeReflectedGroup(result.callableGroups, reflectedGroup->getSlot(),
                        std::move(group));
  }

  return result;
}
