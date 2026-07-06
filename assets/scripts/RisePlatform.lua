-- RisePlatform.lua -- arriveT になるまで画面外に隠れている足場。矢で先送りすると
-- 「今すぐ召喚」できる(=間に合わない穴に橋を架ける)。listenButton=true ならボタン連動リフトになり、
-- 押すたびに上下をトグルする(こちらは時間無視・ボタンが直接制御)。
-- Player.lua の standables に名前を入れれば乗れる。
properties = {
  { name = "arriveT",     type = "float",  default = 10.0, min = 0,   max = 60, label = "現れる時刻(秒)" },
  { name = "riseTime",    type = "float",  default = 0.4,  min = 0.05,max = 3,  label = "せり上がる所要時間" },
  { name = "hideY",       type = "float",  default = -100, min = -200,max = 0,  label = "隠れている時のY" },
  { name = "triggerName", type = "string", default = "",                       label = "矢が当たる的の名前(空なら自分の名前)" },
  { name = "listenButton",type = "bool",   default = false,                    label = "ボタン連動リフト(押すたびに上下をトグル)" },
}

function OnStart(self)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.clock = 0
  self.buttonUp = false
  self.curFrac = 0
  self.transform.position = Vec3.new(self.bx, self.hideY, self.bz)

  local listenName = self.triggerName ~= "" and self.triggerName or self.name
  events:on("time_skip", function(data)
    if data.target ~= listenName then return end
    self.clock = self.clock + data.amount
    FX.spark(self.bx, self.by, self.bz, 12, 0.3, 0.75, 1.0)
  end)

  events:on("button_toggle", function(data)
    if data.target ~= self.name or not self.listenButton then return end
    self.buttonUp = not self.buttonUp
    FX.spark(self.bx, self.by, self.bz, 10, 0.3, 0.75, 1.0)
  end)
end

function OnUpdate(self, dt)
  local frac
  if self.listenButton then
    -- ボタンはトグルの瞬間値しか持たないので、ここだけ滑らかに追従させる
    local targetFrac = self.buttonUp and 1 or 0
    local step = dt / math.max(self.riseTime, 0.05)
    if self.curFrac < targetFrac then
      self.curFrac = math.min(targetFrac, self.curFrac + step)
    else
      self.curFrac = math.max(targetFrac, self.curFrac - step)
    end
    frac = self.curFrac
  else
    self.clock = self.clock + dt
    frac = clamp((self.clock - self.arriveT) / self.riseTime, 0, 1)
  end
  local y = lerp(self.hideY, self.by, frac)
  self.transform.position = Vec3.new(self.bx, y, self.bz)
end
