-- MovingPlatform.lua -- period周期でY方向(上下)に往復する足場。矢で先送りすると位相がずれる
-- (=タイミングを手繰り寄せて乗りやすい位相へ持っていける)。Player.standablesに名前を登録すれば乗れる。
-- Pendulum.lua(X方向版)のY方向版。deadly判定は持たない(足場専用)。
properties = {
  { name = "period",      type = "float", default = 5.0, min = 0.3, max = 20, label = "往復周期(秒)" },
  { name = "amplitude",   type = "float", default = 1.5, min = 0,   max = 10, label = "振れ幅(上下)" },
  { name = "startPhase",  type = "float", default = 0.0, min = 0,   max = 20, label = "開始位相オフセット(秒)" },
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
  self.clock = self.startPhase
  self.ffRemain = 0

  events:on("time_skip", function(data)
    if data.target ~= self.name then return end
    -- 一括加算せず早送り(0.5秒で消化)して、足場が高速で動いて見えるようにする
    self.ffRemain = self.ffRemain + data.amount
    self.ffSpeed = self.ffRemain / 1.5   -- ゆっくり消化(サージが速すぎて避けられない問題への全体調整)
    FX.spark(self.bx, self.transform.position.y, self.bz, 8, 0.3, 0.75, 1.0)
    FX.shockwave(self.bx, self.transform.position.y, self.bz, 10, 6, 0.3, 0.9, 1.0)
  end)

  -- 後戻り(グローバル): 世界時計と一緒に自分の位相も巻き戻る
  self.rwGlow = 0
  events:on("time_rewind", function(data)
    if data.target ~= self.name then return end
    -- 後戻り矢: 一括減算せず逆再生(0.5秒で消化)して、巻き戻る様子を見せる
    self.rwRemain = (self.rwRemain or 0) + (data.amount or 0)
    self.rwSpeed = self.rwRemain / 1.5   -- FFと同じ1.5秒消化(全ギミック統一テンポ。RWだけ3倍速で落下が速すぎた)
    self.rwGlow = 0.1
    local p = self.transform.position
    FX.spark(p.x, p.y, p.z, 10, 0.65, 0.4, 1.0)
    FX.shockwave(p.x, p.y, p.z, 10, 6, 0.65, 0.4, 1.0)
  end)
end

function OnUpdate(self, dt)
  dt = dt * (self.ts or 1)  -- 弓の構え中はスローモーション
  self.clock = self.clock + dt
  if self.ffRemain > 0 then
    local step = math.min(self.ffRemain, self.ffSpeed * dt)
    self.clock = self.clock + step
    self.ffRemain = self.ffRemain - step
  end
  if self.rwRemain and self.rwRemain > 0 then
    -- 対象の時計は0で底打ち。それ以上は戻せない=タイマー返金もされない(戻しすぎは無駄撃ち)
    local step = math.min(self.rwRemain, self.rwSpeed * dt, self.clock)
    if step <= 0 then
      self.rwRemain = 0
    else
      self.clock = self.clock - step
      self.rwRemain = self.rwRemain - step
      self.rwGlow = 0.1
      events:emit("time_refund", { amount = step })
    end
  end
  local ang = math.sin((self.clock / self.period) * math.pi * 2)
  local ny = self.by + ang * self.amplitude
  self.transform.position = Vec3.new(self.bx, ny, self.bz)

  -- TimeWarpシェーダーへ状態を送る: 早送り=1 / 後戻り=2.8 / 通常=0
  local selfE = scene:findEntity(self.name)
  if selfE and selfE:isValid() then
    local eff = 5.0  -- 撃てる=金色の的アピール
    if self.ffRemain > 0 then eff = 1.0
    elseif self.rwGlow > 0 then eff = 2.8 end
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

  -- 早送り中=水色の残像 / 後戻り中=紫の残像。時間操作の向きが色で分かる
  if self.ffRemain > 0 then
    FX.trail(self.bx, ny, self.bz, 0.3, 0.9, 1.0)
  end
  if self.rwGlow > 0 then
    self.rwGlow = self.rwGlow - dt
    FX.trail(self.bx, ny, self.bz, 0.65, 0.4, 1.0)
  end
end
