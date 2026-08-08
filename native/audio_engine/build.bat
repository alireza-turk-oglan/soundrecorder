@echo off


cl /LD /EHsc /std:c++17 /O2 audio_engine.cpp /link ole32.lib uuid.lib /OUT:audio_engine.dll

