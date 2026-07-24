-- Fan.lua -- 上昇気流ファン(Fan_Baseに付ける)。真上のリフト圏内のプレイヤーを押し上げる。
-- 先送り矢: 量×surgePerSkip 秒のサージ(強風)= surgeHeight まで届く高所ルート
-- 後戻り矢: 量×suckPerRewind 秒の【吸い込み】= 風が逆流し、広範囲からファンへ引き寄せる
--   (返金なし=RWの弾数を「引力」に変換する使い方。羽根も逆回転する)
-- 羽根(bladesName)はここから回す(サージ=高速正転/吸い込み=逆転)。
properties = {
  { name = "bladesName",   type = "string", default = "",   label = "羽根エンティティ名" },
  { name = "liftHeight",   type = "float",  default = 3.0,  min = 0.5, max = 20, label = "通常時の気流の高さ" },
  { name = "surgeHeight",  type = "float",  default = 7.0,  min = 1,   max = 24, label = "サージ時の気流の高さ" },
  { name = "strength",     type = "float",  default = 70.0, min = 10,  max = 200,label = "押し上げ加速度" },
  { name = "surgePerSkip", type = "float",  default = 0.8,  min = 0.1, max = 3,  label = "先送り1秒あたりのサージ秒数" },
  { name = "suckPerRewind",type = "float",  default = 0.8,  min = 0.1, max = 3,  label = "後戻り1秒あたりの吸い込み秒数" },
  { name = "zoneHalfW",    type = "float",  default = 0.9,  min = 0.2, max = 4,  label = "気流の半幅" },
  { name = "suckRadius",   type = "float",  default = 5.0,  min = 1,   max = 12, label = "吸い込みの届く半径" },
}

function OnStart(self)
  self.ts = 1.0
  events:on("time_scale", function(d) self.ts = d.scale or 1 end)
  events:on("aim_preview", function(d)
    if d.target == self.name or d.target == self.name .. "X" then
      self.aimPv = { m = d.mode, t = 0.12 }
    end
  end)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.surge = 0
  self.suck = 0
  self.spin = 0

  events:on("time_skip", function(data)
    if data.target ~= self.name and data.target ~= self.name .. "X" then return end
    self.surge = self.surge + (data.amount or 0) * self.surgePerSkip
    self.suck = 0                        -- サージと吸い込みは排他(新しい方が勝つ)
    FX.spark(self.bx, self.by + 0.5, self.bz, 12, 0.3, 0.85, 1.0)
    FX.shockwave(self.bx, self.by, self.bz, 10, 6, 0.3, 0.9, 1.0)
  end)

  events:on("time_rewind", function(data)
    if data.target ~= self.name and data.target ~= self.name .. "X" then return end
    self.suck = self.suck + (data.amount or 0) * self.suckPerRewind
    self.surge = 0
    FX.spark(self.bx, self.by + 0.5, self.bz, 14, 0.65, 0.4, 1.0)
    FX.shockwave(self.bx, self.by + 0.5, self.bz, 14, 8, 0.65, 0.4, 1.0)
  end)
end

function OnUpdate(self, dt)
  local sdt = dt * (self.ts or 1)
  local surging = self.surge > 0
  local sucking = self.suck > 0
  if surging then self.surge = math.max(0, self.surge - sdt) end
  if sucking then self.suck = math.max(0, self.suck - sdt) end

  -- 羽根: 通常=正転 / サージ=高速 / 吸い込み=逆転
  local rate = sucking and -900 or (surging and 1600 or 480)
  self.spin = self.spin + sdt * rate
  local blades = scene:findEntity(self.bladesName)
  if blades and blades:isValid() then
    blades.transform.rotation = Vec3.new(0, self.spin % 360, 0)
  end

  local selfE = scene:findEntity(self.name)
  if selfE and selfE:isValid() then
    local eff = 5.0
    if surging then eff = 1.0
    elseif sucking then eff = 2.8 end
    if self.aimPv then
      self.aimPv.t = self.aimPv.t - dt
      if self.aimPv.t > 0 then
        eff = (self.aimPv.m == "rewind") and 9.5 or 8.5
      else
        self.aimPv = nil
      end
    end
    scene:setMeshEffect(selfE, eff)
  end

  local h = surging and self.surgeHeight or self.liftHeight
  self.fxT = (self.fxT or 0) + sdt
  if sucking then
    -- 吸い込み: 柱状の吸気帯に沿って紫の粒がファンへ向かって流れる
    if self.fxT > 0.05 then
      self.fxT = 0
      local ox = (math.random() - 0.5) * self.zoneHalfW * 3.6
      local oy = (0.6 + math.random() * (self.suckRadius - 1.0)) * (math.random() < 0.8 and -1 or 1)
      FX.trail(self.bx + ox, self.by + 0.6 + oy, self.bz, 0.65, 0.4, 1.0)
    end
  elseif self.fxT > (surging and 0.05 or 0.12) then
    self.fxT = 0
    local ox = (math.random() - 0.5) * self.zoneHalfW * 1.6
    FX.trail(self.bx + ox, self.by + 0.4 + math.random() * h * 0.8, self.bz,
             surging and 0.45 or 0.7, surging and 0.9 or 0.85, 1.0)
  end

  local pl = scene:findEntity("Player")
  if not (pl and pl:isValid()) then return end
  local pp = pl.transform.position

  if sucking then
    -- 吸い込み: ファン正面の【柱状範囲だけ】を縦方向のみ引き寄せる(2026-07-24ユーザー指示:
    -- 旧・放射状の引力は横に離れた場所でもふわっと効いてしまった。横力は元から与えない)。
    -- 頭上ファン=真下の柱を吸い上げ / 地上ファン=真上の柱を引き降ろす
    local dx = pp.x - self.bx
    local dy = (self.by + 0.6) - pp.y   -- +なら吸い上げ / -なら引き降ろし
    if math.abs(dx) < self.zoneHalfW * 2.0 and math.abs(dy) > 0.2 and math.abs(dy) < self.suckRadius then
      local pull = self.strength * 1.1 * (1.0 - math.abs(dy) / self.suckRadius + 0.25)
      events:emit("fan_force", { ay = (dy > 0) and pull or -pull })
    end
  elseif math.abs(pp.x - self.bx) < self.zoneHalfW and pp.y > self.by and pp.y < self.by + h then
    local frac = 1.0 - (pp.y - self.by) / h
    events:emit("fan_force", { ay = self.strength * (0.35 + 0.65 * frac) })
  end
end
