local PARAM_TABLE_KEY = 69
local PARAM_TABLE_PREFIX = "ESC_TH_"

local MAV_SEVERITY = {EMERGENCY=0, ALERT=1, CRITICAL=2, ERROR=3, WARNING=4, NOTICE=5, INFO=6, DEBUG=7}

-- bind a parameter to a variable given
local function bind_param(name)
    local p = Parameter()
    assert(p:init(name), string.format('could not find %s parameter', name))
    return p
end

-- add a parameter and bind it to a variable
local function bind_add_param(name, idx, default_value)
    assert(param:add_param(PARAM_TABLE_KEY, idx, name, default_value), string.format('could not add param %s', name))
    return bind_param(PARAM_TABLE_PREFIX .. name)
end

-- setup script specific parameters
assert(param:add_table(PARAM_TABLE_KEY, PARAM_TABLE_PREFIX, 8), 'could not add param table')

-- Define parameters for ESC telemetry
ESC_TH_ENABLE = bind_add_param("ENABLE", 1, 0)
ESC_TH_POLES = bind_add_param("POLES", 2, 14)
ESC_TH_OFS = bind_add_param("OFS", 3, 0)

if ESC_TH_ENABLE:get() ~= 1 then
   gcs:send_text(MAV_SEVERITY.INFO, "ESC_TH: disabled")
   return
end

local uart = serial:find_serial(1) -- first scripting serial
if not uart then
   gcs:send_text(MAV_SEVERITY.ERROR, "ESC_TH: unable to find serial port")
   return
end
uart:begin(38400)

-- local function read_bytes(n)
--    local ret = ""
--    for _ = 1, n do
--       -- Read a single character (byte) from the UART
--       local char = uart:read()  -- Read one byte
--       if char then
--          ret = ret .. char
--       else
--          -- Handle error or timeout when reading from UART
--          return nil
--       end
--    end
--    return ret
-- end

-- local function read_bytes(n)
--    local ret = ""
--    for _ = 1, n do
--       local byte_value=uart:read()
--       local hex = string.format("%02X",byte_value)
--       ret = ret .. hex .. " "
--     end
--     return ret, 50
--  end

function string.starts(String,Start)
   return string.sub(String,1,string.len(Start))==Start
end

local function read_bytes(n)
   local ret = ""
   for _ = 1, n do
      -- if (string.starts(string.char(uart:read()),"SPD")) then
      ret = ret .. string.char(uart:read())
   end
   -- if (string.starts(ret,"SPD")) then
   --    return ret
   -- end
   return ret
end

-- local function read_bytes(n)
--    local ret = {}
--    for _ = 1, n do
--       ret[#ret + 1] = uart:read()
--    end
--    return ret
-- end

local function discard_pending()
   local n = uart:available():toint()
   for _ = 1, n do
      uart:read()
   end
end

--[[
   xmodem CRC implementation thanks to https://github.com/cloudwu/skynet
   under MIT license
--]]
local XMODEMCRC16Lookup = {
	0x0000,0x1021,0x2042,0x3063,0x4084,0x50a5,0x60c6,0x70e7,
	0x8108,0x9129,0xa14a,0xb16b,0xc18c,0xd1ad,0xe1ce,0xf1ef,
	0x1231,0x0210,0x3273,0x2252,0x52b5,0x4294,0x72f7,0x62d6,
	0x9339,0x8318,0xb37b,0xa35a,0xd3bd,0xc39c,0xf3ff,0xe3de,
	0x2462,0x3443,0x0420,0x1401,0x64e6,0x74c7,0x44a4,0x5485,
	0xa56a,0xb54b,0x8528,0x9509,0xe5ee,0xf5cf,0xc5ac,0xd58d,
	0x3653,0x2672,0x1611,0x0630,0x76d7,0x66f6,0x5695,0x46b4,
	0xb75b,0xa77a,0x9719,0x8738,0xf7df,0xe7fe,0xd79d,0xc7bc,
	0x48c4,0x58e5,0x6886,0x78a7,0x0840,0x1861,0x2802,0x3823,
	0xc9cc,0xd9ed,0xe98e,0xf9af,0x8948,0x9969,0xa90a,0xb92b,
	0x5af5,0x4ad4,0x7ab7,0x6a96,0x1a71,0x0a50,0x3a33,0x2a12,
	0xdbfd,0xcbdc,0xfbbf,0xeb9e,0x9b79,0x8b58,0xbb3b,0xab1a,
	0x6ca6,0x7c87,0x4ce4,0x5cc5,0x2c22,0x3c03,0x0c60,0x1c41,
	0xedae,0xfd8f,0xcdec,0xddcd,0xad2a,0xbd0b,0x8d68,0x9d49,
	0x7e97,0x6eb6,0x5ed5,0x4ef4,0x3e13,0x2e32,0x1e51,0x0e70,
	0xff9f,0xefbe,0xdfdd,0xcffc,0xbf1b,0xaf3a,0x9f59,0x8f78,
	0x9188,0x81a9,0xb1ca,0xa1eb,0xd10c,0xc12d,0xf14e,0xe16f,
	0x1080,0x00a1,0x30c2,0x20e3,0x5004,0x4025,0x7046,0x6067,
	0x83b9,0x9398,0xa3fb,0xb3da,0xc33d,0xd31c,0xe37f,0xf35e,
	0x02b1,0x1290,0x22f3,0x32d2,0x4235,0x5214,0x6277,0x7256,
	0xb5ea,0xa5cb,0x95a8,0x8589,0xf56e,0xe54f,0xd52c,0xc50d,
	0x34e2,0x24c3,0x14a0,0x0481,0x7466,0x6447,0x5424,0x4405,
	0xa7db,0xb7fa,0x8799,0x97b8,0xe75f,0xf77e,0xc71d,0xd73c,
	0x26d3,0x36f2,0x0691,0x16b0,0x6657,0x7676,0x4615,0x5634,
	0xd94c,0xc96d,0xf90e,0xe92f,0x99c8,0x89e9,0xb98a,0xa9ab,
	0x5844,0x4865,0x7806,0x6827,0x18c0,0x08e1,0x3882,0x28a3,
	0xcb7d,0xdb5c,0xeb3f,0xfb1e,0x8bf9,0x9bd8,0xabbb,0xbb9a,
	0x4a75,0x5a54,0x6a37,0x7a16,0x0af1,0x1ad0,0x2ab3,0x3a92,
	0xfd2e,0xed0f,0xdd6c,0xcd4d,0xbdaa,0xad8b,0x9de8,0x8dc9,
	0x7c26,0x6c07,0x5c64,0x4c45,0x3ca2,0x2c83,0x1ce0,0x0cc1,
	0xef1f,0xff3e,0xcf5d,0xdf7c,0xaf9b,0xbfba,0x8fd9,0x9ff8,
	0x6e17,0x7e36,0x4e55,0x5e74,0x2e93,0x3eb2,0x0ed1,0x1ef0
}

local function crc_xmodem(bytes)
	local crc = 0
	for i=1,#bytes do
		local b = string.byte(bytes,i,i)
		crc = ((crc<<8) & 0xffff) ~ XMODEMCRC16Lookup[(((crc>>8)~b) & 0xff) + 1]
	end
    return crc
end

local temp_table = {
   { 241, 	0}, 	{ 240, 	1}, 	{ 239, 	2}, 	{ 238, 	3}, 	{ 237, 	4}, 	{ 236, 	5}, 	{ 235, 	6}, 	{ 234, 	7}, 	{ 233, 	8}, 	{ 232, 	9},
   { 231, 	10}, 	{ 230, 	11}, 	{ 229, 	12}, 	{ 228, 	13}, 	{ 227, 	14}, 	{ 226, 	15}, 	{ 224, 	16}, 	{ 223, 	17}, 	{ 222, 	18}, 	{ 220, 	19},
   { 219, 	20}, 	{ 217, 	21}, 	{ 216, 	22}, 	{ 214, 	23}, 	{ 213, 	24}, 	{ 211, 	25}, 	{ 209, 	26}, 	{ 208, 	27}, 	{ 206, 	28}, 	{ 204, 	29},
   { 202, 	30}, 	{ 201, 	31}, 	{ 199, 	32}, 	{ 197, 	33}, 	{ 195, 	34}, 	{ 193, 	35}, 	{ 191, 	36}, 	{ 189, 	37}, 	{ 187, 	38}, 	{ 185, 	39},
   { 183, 	40}, 	{ 181, 	41}, 	{ 179, 	42}, 	{ 177, 	43}, 	{ 174, 	44}, 	{ 172, 	45}, 	{ 170, 	46}, 	{ 168, 	47}, 	{ 166, 	48}, 	{ 164, 	49},
   { 161, 	50}, 	{ 159, 	51}, 	{ 157, 	52}, 	{ 154, 	53}, 	{ 152, 	54}, 	{ 150, 	55}, 	{ 148, 	56}, 	{ 146, 	57}, 	{ 143, 	58}, 	{ 141, 	59},
   { 139, 	60}, 	{ 136, 	61}, 	{ 134, 	62}, 	{ 132, 	63}, 	{ 130, 	64}, 	{ 128, 	65}, 	{ 125, 	66}, 	{ 123, 	67}, 	{ 121, 	68}, 	{ 119, 	69},
   { 117, 	70}, 	{ 115, 	71}, 	{ 113, 	72}, 	{ 111, 	73}, 	{ 109, 	74}, 	{ 106, 	75}, 	{ 105, 	76}, 	{ 103, 	77}, 	{ 101, 	78}, 	{ 99, 	79},
   { 97, 	80}, 	{ 95, 	81}, 	{ 93, 	82}, 	{ 91, 	83}, 	{ 90, 	84}, 	{ 88, 	85}, 	{ 85, 	86}, 	{ 84, 	87}, 	{ 82, 	88}, 	{ 81, 	89},
   { 79, 	90}, 	{ 77, 	91}, 	{ 76, 	92}, 	{ 74, 	93}, 	{ 73, 	94}, 	{ 72, 	95}, 	{ 69, 	96}, 	{ 68, 	97}, 	{ 66, 	98}, 	{ 65, 	99},
   { 64, 	100}, 	{ 62, 	101}, 	{ 62, 	102}, 	{ 61, 	103}, 	{ 59, 	104}, 	{ 58, 	105}, 	{ 56, 	106}, 	{ 54, 	107}, 	{ 54, 	108}, 	{ 53, 	109},
   { 51, 	110}, 	{ 51, 	111}, 	{ 50, 	112}, 	{ 48, 	113}, 	{ 48, 	114}, 	{ 46, 	115}, 	{ 46, 	116}, 	{ 44, 	117}, 	{ 43, 	118}, 	{ 43, 	119},
   { 41, 	120}, 	{ 41, 	121}, 	{ 39, 	122}, 	{ 39, 	123}, 	{ 39, 	124}, 	{ 37, 	125}, 	{ 37, 	126}, 	{ 35, 	127}, 	{ 35, 	128}, 	{ 33, 	129},
}

local function temperature_decode(temp_raw)
  for i = 1, #temp_table do
     if temp_table[i][1] <= temp_raw then
        return temp_table[i][2]
     end
  end
end

-- local file_name="telem_esc_data.txt"
-- local file
-- local function write_to_file(var_write)

--    if not file then
--      error("Could not open file")
--    end
 
--    -- write data
--    -- separate with comas and add a carriage return
--    file:write(var_write .. "\n")
 
--    -- make sure file is upto date
--    file:flush()
 
-- end

local function update()
   local n_bytes = uart:available():toint()
   -- if n_bytes < 10 then
   --    return
   -- end
   
   local s = read_bytes(n_bytes)
   -- write_to_file(s)
   -- gcs:send_text(5,string.format("n_bytes=%d",n_bytes))
   -- gcs:send_text(6,string.format("s=%s", s))

   -- s = s:sub(4, -3)
   -- local tim = tonumber(s:sub(1, 4), 10)
   -- local spd = tonumber(s:sub(5, 8), 10)
   -- local tmos = tonumber(s:sub(9, 12), 10)
   -- local tmot = tonumber(s:sub(13, 16), 10)
   -- local tmcx = tonumber(s:sub(17, 28), 10)
   -- local curi = tonumber(s:sub(29, 32), 10)
   -- local volt = tonumber(s:sub(33, 36), 10)
   -- local pwac = tonumber(s:sub(37, 40), 10)
   -- local sys = tonumber(s:sub(41, 52), 10)
   -- local et1 = tonumber(s:sub(53, 64), 10)
   -- local et2 = tonumber(s:sub(65), 10)
   
   local spd = string.match(s, "SPD:(%w+)")
   local tmos = string.match(s,"TMOS:(%w+)")
   local tmot = string.match(s,"TMOT:(%w+)")
   local tmcx = string.match(s,"TMCX:(%d+)")
   local volt = string.match(s,"VOLT:(%d+)")
   local pwac = string.match(s,"PWAC:(%w+)")
   local sys = string.match(s,"SYS:(%w+)")
   local spd1 = tonumber(spd,16)
   local tmos1 = tonumber(tmos,16)
   local tmot1 = tonumber(tmot,16)
   local tmcx1 = tonumber(tmcx,16)
   local volt1 = tonumber(volt,16)
   local pwac1 = tonumber(pwac,16)
   local sys1 = tonumber(sys,16)
   -- tmos1 = temperature_decode(tmos1)
   -- gcs:send_text(6,string.format("spd:%s",spd))


   if spd and tmos and tmot and tmcx and volt and pwac and sys then
      local telem_data = ESCTelemetryData()
      
      -- -- Update telemetry data
      telem_data:voltage(volt1 / 100)  -- Convert to volts
      telem_data:temperature_cdeg(tmos1)
      
      -- --Display on Quick tab
      gcs:send_named_float('temp_esc',tmos1)
      gcs:send_named_float('voltage',volt1 / 100)
      gcs:send_named_float('spd',spd1)
   else
      -- Handle parsing error
      gcs:send_text(MAV_SEVERITY.ERROR, "ESC_TH: parsing error")
   end
   return update, 1000
end

-- file = io.open(file_name, "a")
-- if not file then
--   error("Could not make file")
-- end

gcs:send_text(MAV_SEVERITY.ALERT, "ESC_HW: loaded")

return update, 1300