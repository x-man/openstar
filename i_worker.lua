

if ngx.worker.id() ~= 0 then return end

local handler

-- dict 清空过期内存
local function flush_expired_dict()
	local dict_list = {"token_dict","count_dict","config_dict","host_dict","ip_dict","limit_ip_dict"}
	for i,v in ipairs(dict_list) do
		ngx.shared[v]:flush_expired()
	end
end

-- 拉取config_dict配置数据
local function pull_redisConfig()
	local http = require "resty.http"
	local httpc = http.new()

	-- The generic form gives us more control. We must connect manually.
	httpc:set_timeout(500)
	httpc:connect("127.0.0.1", 5460)

	-- And request using a path, rather than a full URI.
	local res, err = httpc:request{
	  path = "/api/redis?action=pull&key=all_dict",
	  headers = {
	      ["Host"] = "127.0.0.1:5460",
	  },
	}

	optl.writefile(config_base.logPath.."i_worker.log","pull_redisConfig: "..(res or err))
	if not res then
		ngx.log(ngx.ERR, "failed to pull_redisConfig request: ", err)
		return
	else
		return true
	end

end

-- 推送count_dict统计、计数等
local function push_count_dict()
	local http = require "resty.http"
	local httpc = http.new()

	-- The generic form gives us more control. We must connect manually.
	httpc:set_timeout(500)
	httpc:connect("127.0.0.1", 5460)

	-- And request using a path, rather than a full URI.
	local res, err = httpc:request{
	  path = "/api/redis?action=push&key=count_dict",
	  headers = {
	      ["Host"] = "127.0.0.1:5460",
	  },
	}

	optl.writefile(config_base.logPath.."i_worker.log","push_count_dict: "..(res or err))
	if not res then
		ngx.log(ngx.ERR, "failed to push_count_dict request: ", err)
		return
	else
		return true
	end

end

-- 保存config_dict、host_dict到本机文件
local function save_configFile()
	local http = require "resty.http"
	local httpc = http.new()

	-- The generic form gives us more control. We must connect manually.
	httpc:set_timeout(500)
	httpc:connect("127.0.0.1", 5460)

	-- And request using a path, rather than a full URI.
	local res, err = httpc:request{
	  path = "/api/config?action=save&mod=all_mod",
	  headers = {
	      ["Host"] = "127.0.0.1:5460",
	  },
	}

	optl.writefile(config_base.logPath.."i_worker.log","save_configFile: "..(res or err))
	if not res then
		ngx.log(ngx.ERR, "failed to save_configFile request: ", err)
		return
	else
		return true
	end

end

handler = function()
	-- do something
	local config_dict = ngx.shared.config_dict
	local config_base = cjson_safe.decode(config_dict:get("base")) or {}
	local timeAt = config_base.autoSync.timeAt or 5

	-- 如果 auto Sync 开启 就定时从redis 拉取配置并推送一些计数
	if config_base.autoSync.state == "on" then
		if pull_redisConfig() then
			save_configFile()
		end
	end

	--推送count_dict到redis
	push_count_dict()

	--清空过期内存
	ngx.thread.spawn(flush_expired_dict)

	--
	local ok, err = ngx.timer.at(timeAt, handler)
	if not ok then
		ngx.log(ngx.ERR, "failed to startup handler worker...", err)
	end
end

local ok, err = ngx.timer.at(0, handler)
if not ok then
	ngx.log(ngx.ERR, "failed to startup handler worker...", err)
end