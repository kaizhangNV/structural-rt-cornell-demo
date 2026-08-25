module rt_pipeline;

import slang.raytracing;
import shared;

// These files are implementation fragments of this module, not separately imported modules.
// Keeping this short table of contents makes every synthesized stage available from rt_pipeline
// while allowing the hit, miss, layout, and ray-generation code to remain in focused files.
__include hit;
__include miss;
__include program_layout;
__include raygen;
