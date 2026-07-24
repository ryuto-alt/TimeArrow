-- StandNeedle.lua -- 起き上がる針山。
--   最初は寝ていて、プレイヤーが画面内(triggerDist)まで近づくと「端を軸に」起き上がって道を塞ぐ。
--   後戻し矢: 矢の秒数ぶんだけ寝転がる(=通れる時間窓)。時間が尽きると警告点滅ののち再起立。
--   先送り矢: 寝ていても即座に起き上がる(時間が進む=また立ちはだかる)。
-- 回転軸は端(hinge=1で右端/-1で左端)。当たり判定は回転を使わず縦横を入れ替えたAABB+接地面固定
-- (scale=実寸規約を維持)。見た目はTimeWarpシェーダーで「撃てる対象」の金色発光を出す。
properties = {
  { name = "deadly",      type = "bool",  default = true,  label = "接触で死亡" },
  { name = "hitScale",    type = "float", default = 0.6, min = 0.2, max = 1.5, label = "当たり判定の見た目に対する倍率" },
  { name = "tiltTime",    type = "float", default = 0.45, min = 0.1, max = 2.0, label = "寝転がりの所要秒" },
  { name = "riseTime",    type = "float", default = 1.5,  min = 0.1, max = 4.0, label = "起き上がりの所要秒(ゆっくり=脅かさない)" },
  { name = "standHeight", type = "float", default = 3.0,  min = 0.5, max = 6.0, label = "起立時の高さ(ジャンプ頂点約2.5より高く=飛び越え不可)" },
  { name = "hinge",       type = "float", default = -1.0, min = -1.0, max = 1.0, label = "起立の軸(-1=左端: 牙が左=来る側を向く / 1=右端)" },
  { name = "triggerDist", type = "float", default = 11.0, min = 2.0, max = 40.0, label = "この距離まで近づくと起立(≒画面に入る距離)" },
}

local function overlapAABB(ax, ay, ahw, ahh, bx, by, bhw, bhh)
  return math.abs(ax - bx) < (ahw + bhw) and math.abs(ay - by) < (ahh + bhh)
end

function OnStart(self)
  self.ts = 1.0
  events:on("time_scale", function(d) self.ts = d.scale or 1 end)

  local p, s = self.transform.position, self.transform.scale
  self.bx, self.bz = p.x, p.z
  self.sx, self.sy, self.sz = s.x, s.y, s.z   -- 寝ている時の実寸(横長: 例 1.6 x 0.6)
  self.standLen = math.max(self.sx, self.standHeight)   -- 起立時は伸びて飛び越え不可の高さになる
  self.footY = p.y - s.y * 0.5           -- 接地面
  self.hingeX = self.bx + self.hinge * self.sx * 0.5   -- 回転軸(端)
  self.u = 0.0                           -- 0=寝 / 1=立。最初は寝ている
  self.target = 0.0
  self.armed = false                     -- 一度でも起き上がったか
  self.downRemain = 0                    -- 後戻し矢で寝ていられる残り秒数

  events:on("time_rewind", function(d)
    if d.target ~= self.name then return end
    -- 矢の秒数ぶんだけ寝る(連射で延長可)
    self.downRemain = self.downRemain + (d.amount or 0)
    self.target = 0
    FX.spark(self.hingeX, self.footY + 0.6, self.bz, 12, 0.65, 0.4, 1.0)
    FX.shockwave(self.bx, self.footY + 0.5, self.bz, 8, 5, 0.65, 0.4, 1.0)
  end)
  events:on("time_skip", function(d)
    if d.target ~= self.name then return end
    self.downRemain = 0
    self.target = 1
    self.armed = true
    self.ffGlow = 0.3
    FX.spark(self.bx, self.footY + 0.4, self.bz, 12, 0.3, 0.75, 1.0)
    FX.shockwave(self.bx, self.footY + 0.5, self.bz, 8, 5, 0.3, 0.75, 1.0)
  end)
  events:on("aim_preview", function(d)
    if d.target == self.name then self.aimPv = { m = d.mode, t = 0.12 } end
  end)
end

function OnUpdate(self, dt)
  dt = dt * (self.ts or 1)
  local pl = scene:findEntity("Player")
  local pp = (pl and pl:isValid()) and pl.transform.position or nil

  -- 画面に入ったら初回起立(不意打ちにならないよう、まだ距離があるうちに立つ)
  if not self.armed and pp and math.abs(pp.x - self.bx) < self.triggerDist then
    self.armed = true
    self.target = 1
    FX.shockwave(self.bx, self.footY + 0.3, self.bz, 10, 6, 1.0, 0.8, 0.4)
    fx:pulse(0.08)
  end

  -- 寝ている残り時間の消化 → 尽きたら再起立
  if self.downRemain > 0 then
    self.downRemain = math.max(0, self.downRemain - dt)
    if self.downRemain == 0 and self.armed then
      self.target = 1
    end
  end

  -- 起き/寝モーション(端ヒンジ)
  if self.target ~= self.u then
    local dir = (self.target > self.u) and 1 or -1
    self.u = clamp(self.u + dir * dt / ((dir > 0) and self.riseTime or self.tiltTime), 0, 1)
    if math.random() < 0.4 then
      FX.trail(self.hingeX - self.hinge * math.random() * self.sx, self.footY + 0.15, self.bz, 0.6, 0.55, 0.45)
    end
    if self.u == self.target then
      FX.spark(self.hingeX, self.footY + 0.2, self.bz, 10, 0.8, 0.7, 0.5)
      fx:pulse(0.06)
    end
  end

  -- 寝ている間はPlayer側の矢判定の縦膨張(最低±0.8)を外してもらう(2026-07-24:
  -- 寝た針山が水平弾道を吸ってしまう指摘)。状態が変わった時だけ通知
  local lying = self.u < 0.3
  if lying ~= self.lastLying then
    self.lastLying = lying
    events:emit("flat_target", { name = self.name, on = lying })
  end

  local ease = self.u * self.u * (3 - 2 * self.u)   -- smoothstep
  -- 起き上がりに合わせて長さが standLen まで伸びる(=起立時はジャンプで飛び越えられない高さ)
  local L = self.sx + (self.standLen - self.sx) * ease
  local th = math.rad(90.0 * ease)
  local cx = self.hingeX - self.hinge * (L * 0.5) * math.cos(th)
  local cy = self.footY + (L * 0.5) * math.sin(th) + (self.sy * 0.5) * math.cos(th)
  self.transform.position = Vec3.new(cx, cy, self.bz)
  self.transform.scale = Vec3.new(L, self.sy, self.sz)
  -- Z正回転=画面反時計回り(DirectXMath)。左端ヒンジ(hinge=-1)は+90°で牙が左を向く
  self.transform.rotation = Vec3.new(0, 0, -self.hinge * 90.0 * ease)

  -- シェーダー帯: 金=撃てる / 紫=寝ている(残り時間) / 点滅=まもなく再起立 / 照準ロック=8.5/9.5
  local selfE = scene:findEntity(self.name)
  if selfE and selfE:isValid() then
    local eff = 5.0
    if self.downRemain > 0 then
      if self.downRemain < 0.9 then
        eff = 6.0 + math.sin(self.downRemain * 25.0) * 0.9   -- 警告: 起き上がる直前
      else
        eff = 2.8                                            -- 後戻し中の紫
      end
    end
    if self.ffGlow and self.ffGlow > 0 then
      self.ffGlow = self.ffGlow - dt
      eff = 1.0
    end
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

  if not self.deadly then return end
  if not pp then return end
  local hw = (L * (1 - ease) + self.sy * ease) * 0.5
  local hh = (self.sy * (1 - ease) + L * ease) * 0.5
  if overlapAABB(cx, cy, hw * self.hitScale, hh * self.hitScale, pp.x, pp.y, 0.30, 0.42) then
    events:emit("player_died", {})
  end
end
