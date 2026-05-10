// cactus_service.dart — DEPRECATED
//
// The Cactus SDK (GGUF / llama.cpp) has been replaced by LiteRT-LM which
// provides native vision support for Gemma 4 E2B without a separate mmproj
// file.  Inference now happens in PharosLiteRTModule.kt via MethodChannel.
//
// This file is kept only to re-export kPharosSystemPrompt so that any old
// import paths still compile while the codebase is being cleaned up.
// You can delete this file once all imports point to pharos_prompts.dart.

export 'pharos_prompts.dart' show kPharosSystemPrompt;
