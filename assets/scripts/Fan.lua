-- Fan.lua -- 上昇気流ファン(Fan_Baseに付ける)。真上のリフト圏内にいるプレイヤーを押し上げる。
-- 通常は liftHeight まで届く弱い気流。先送り矢を当てると量×surgePerSkip 秒のあいだ
-- サージ(強風)になり surgeHeight まで届く=FFでしか登れない高所を作れる。
-- 後戻り矢はサージ中ならサージを吐き出して返金(時計は実時間で回る)。
-- 羽根(bladesName)はここから回す(サージ中は高速回転)。
properties = {
  { name = "bladesName",   type = "string", default = "",   label = "羽根エンティティ名" },
  { name = "liftHeight",   type = "float",  default = 3.0,  min = 0.5, max = 20, label = "通常時の気流の高さ" },
  { name = "surgeHeight",  type = "float",  default = 7.0,  min = 1,   max = 24, label = "サージ時の気流の高さ" },
  { name = "strength",     type = "float",  default = 70.0, min = 10,  max = 200,label = "押し上げ加速度" },
  { name = "surgePerSkip", type = "float",  default = 0.8,  min = 0.1, max = 3,  label = "先送り1秒あたりのサージ秒数" },
  { name = "zoneHalfW",    type = "float",  default = 0.9,  min = 0.2, max = 4,  label = "気流の半幅" },
}

function OnStart(self)
  self.ts = 1.0
  events:on("time_scale", function(d) self.ts = d.scale or 1 end)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.surge = 0
  self.spin = 0

  events:on("time_skip", function(data)
    if data.target ~= self.name then return end
    self.surge = self.surge + (data.amount or 0) * self.surgePerSkip
    FX.spark(self.bx, self.by + 0.5, self.bz, 12, 0.3, 0.85, 1.0)
    FX.shockwave(self.bx, self.by, self.bz, 10, 6, 0.3, 0.9, 1.0)
  end)

  events:on("time_rewind", function(data)
    if data.target ~= self.name then return end
    -- サージの残りを吐き出して返金(サージがなければ何も起きない=無駄撃ち)
    local give = math.min(self.surge / math.max(self.surgePerSkip, 0.01), data.amount or 0)
    if give > 0 then
      self.surge = self.surge - give * self.surgePerSkip
      events:emit("time_refund", { amount = give })
      FX.spark(self.bx, self.by + 0.5, self.bz, 10, 0.65, 0.4, 1.0)
    end
  end)
  pcall(function() scene:setColor(scene:findEntity(self.name), 0.30, 0.34, 0.42, 1.0) end)
  pcall(function() scene:setColor(scene:findEntity(self.bladesName), 0.45, 0.85, 1.0, 1.0) end)

end

function OnUpdate(self, dt)
  local sdt = dt * (self.ts or 1)
  local surging = self.surge > 0
  if surging then
    self.surge = math.max(0, self.surge - sdt)
  end

  -- 羽根の回転(サージ中は3倍速)
  self.spin = self.spin + sdt * (surging and 1600 or 480)
  local blades = scene:findEntity(self.bladesName)
  if blades and blades:isValid() then
    blades.transform.rotation = Vec3.new(0, self.spin % 360, 0)
  end

  local h = surging and self.surgeHeight or self.liftHeight
  -- 気流の見た目(細かい上昇パーティクル)
  self.fxT = (self.fxT or 0) + sdt
  if self.fxT > (surging and 0.05 or 0.12) then
    self.fxT = 0
    local ox = (math.random() - 0.5) * self.zoneHalfW * 1.6
    FX.trail(self.bx + ox, self.by + 0.4 + math.random() * h * 0.8, self.bz,
             surging and 0.45 or 0.7, surging and 0.9 or 0.85, 1.0)
  end

  -- プレイヤーが気流圏内なら押し上げ力を送る
  local pl = scene:findEntity("Player")
  if not (pl and pl:isValid()) then return end
  local pp = pl.transform.position
  if math.abs(pp.x - self.bx) < self.zoneHalfW and pp.y > self.by and pp.y < self.by + h then
    -- 上端に近いほど弱く(頂上でホバリングできる)
    local frac = 1.0 - (pp.y - self.by) / h
    events:emit("fan_force", { ay = self.strength * (0.35 + 0.65 * frac) })
  end
end
