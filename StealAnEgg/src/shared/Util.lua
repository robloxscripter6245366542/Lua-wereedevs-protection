local Util = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Util.FormatNumber(n: number): string
	n = math.floor(n)
	if n < 1000 then
		return tostring(n)
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local scaled = n / (1000 ^ tier)
	local text = if scaled >= 100 then string.format("%d", scaled) else string.format("%.1f", scaled)
	text = text:gsub("%.0$", "")
	return text .. SUFFIXES[tier + 1]
end

function Util.FormatCash(n: number): string
	return "$" .. Util.FormatNumber(n)
end

function Util.FormatTime(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return string.format("%dh %02dm", seconds // 3600, (seconds % 3600) // 60)
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- entries: array of tables with a Weight field (or weightFn(entry) override)
function Util.WeightedPick<T>(entries: { T }, weightFn: (T) -> number, rng: Random?): T
	local random = rng or Random.new()
	local total = 0
	for _, entry in entries do
		total += weightFn(entry)
	end
	local roll = random:NextNumber() * total
	for _, entry in entries do
		roll -= weightFn(entry)
		if roll <= 0 then
			return entry
		end
	end
	return entries[#entries]
end

return Util
