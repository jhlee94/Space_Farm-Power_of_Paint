-- SIE CONFIDENTIAL
-- PhyreEngine(TM) Package 3.18.0.0
-- Copyright (C) 2016 Sony Interactive Entertainment Inc.
-- All Rights Reserved.


Trace = { level = 0  }  -- exported table

-- Description:
--
--
local function dump(level,msg)
	if args then
		output = ""		
	 	for i,v in ipairs(args) do
			output = output .. tostring(v) .. " "
		end
		print(level .. output )
	end
end
  

-- Description:
--
--
function Trace.setLevel(level)
	Trace.level = level
end


-- Description:
--
--
function Trace.getLevel()
	return Trace.level
end 

-- Description:
--
--
function Trace.error(...)
	dump("ERROR: ", {...})
end 


-- Description:
--
--
function Trace.warn(...)
	if Trace.level >= 1 then
		args = {...}
		dump("WARN: ", args)
	end
end 
 

-- Description:
--
--
function Trace.info(...)
	if Trace.level >= 2 then
		args = {...}
		dump("INFO: ", args)
	end
end 
 

-- Description:
-- Unconditional output for testing using Phyre Framework script Expect command
--
function Trace.echo(...)
	dump("ECHO: ", {...})
end 
