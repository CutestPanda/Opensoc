for %%f in (transcript *.o *.wlf core* *.obj *.dll *.h vsim_stacktrace.vstf log.txt *.exp *.lib) do (
	if exist %%f del %%f
)
rmdir /s /q work  2> nul
