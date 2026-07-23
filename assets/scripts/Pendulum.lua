-- Pendulum.lua -- period周期でX方向に振り子運動する足場/刃。矢で先送りすると位相がずれる
-- (=タイミングを手繰り寄せて安全な位相へ持っていける)。deadly=trueなら刃、falseなら足場として使う。
-- 当たり判定は自分の transform.scale から出すAABB。
-- oneWay=true: 往復せず左端(bx-amplitude)→右端(bx+amplitude)へ period 秒かけて片道航行して停止。
-- 待てば渡れるが、先送り矢で到着を前倒しできる(後戻り矢で呼び戻し=乗り損ねの救済)。
properties = {
  { name = "period",      type = "float", default = 3.0, min = 0.3, max = 30, label = "往復周期(片道モードでは片道時間)(秒)" },
  { name = "amplitude",   type = "float", default = 3.0, min = 0,   max = 20, label = "振れ幅" },
  { name = "startPhase",  type = "float", default = 0.0, min = 0,   max = 20, label = "開始位相オフセット(秒)" },
  { name = "deadly",      type = "bool",  default = false,                    label = "刃として扱う(接触で死亡)" },
  { name = "hitScale",    type = "float", default = 0.8, min = 0.2, max = 1.5,label = "当たり判定の見た目に対する倍率" },
  { name = "oneWay",      type = "bool",  default = false,                    label = "片道モード(左端→右端へ渡って停止)" },
}

local function overlapAABB(ax, ay, ahw, ahh, bx, by, bhw, bhh)
  return math.abs(ax - bx) < (ahw + bhw) and math.abs(ay - by) < (ahh + bhh)
end

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
    -- 一括加算せず早送り(0.5秒で消化)して、振り子が高速で振れて見えるようにする
    self.ffRemain = self.ffRemain + data.amount
    self.ffSpeed = self.ffRemain / 1.5   -- ゆっくり消化(サージが速すぎて避けられない問題への全体調整)
    FX.spark(self.transform.position.x, self.by, self.bz, 8, 0.3, 0.75, 1.0)
    FX.shockwave(self.transform.position.x, self.by, self.bz, 10, 6, 0.3, 0.9, 1.0)
  end)

  -- 後戻り(グローバル): 位相も世界時計と一緒に巻き戻る
  self.rwGlow = 0
  events:on("time_rewind", function(data)
    if data.target ~= self.name then return end
    -- 後戻り矢: 一括減算せず逆再生(0.5秒で消化)して、巻き戻る様子を見せる
    self.rwRemain = (self.rwRemain or 0) + (data.amount or 0)
    self.rwSpeed = self.rwRemain / 0.5
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
  local nx
  if self.oneWay then
    -- 片道航行: 到着したら時計を止める(超過分が溜まらないので後戻り矢が即効く)
    if self.clock > self.period then self.clock = self.period end
    nx = self.bx - self.amplitude + (self.clock / self.period) * self.amplitude * 2
  else
    local ang = math.sin((self.clock / self.period) * math.pi * 2)
    nx = self.bx + ang * self.amplitude
  end
  self.transform.position = Vec3.new(nx, self.by, self.bz)
  -- 丸ノコの回転(スローモーション中はゆっくり回る=時間の速度が見える)。
  -- deadly=false(フェリー等の乗れる足場)は回転させない
  if self.deadly then
    self.transform.rotation = Vec3.new(0, 0, -(self.clock * 420) % 360)
  else
    self.transform.rotation = Vec3.new(0, 0, 0)
  end

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

  -- 早送り=水色 / 後戻り=紫 の残像で時間操作の向きを見せる
  if self.ffRemain > 0 then
    FX.trail(nx, self.by, self.bz, 0.3, 0.9, 1.0)
  end
  if self.rwGlow > 0 then
    self.rwGlow = self.rwGlow - dt
    FX.trail(nx, self.by, self.bz, 0.65, 0.4, 1.0)
  end

  -- 早送り中は途中の位相を"経由しただけ"なので即死判定しない(従来のワープと同じ扱い)
  if not self.deadly or self.ffRemain > 0 then return end
  local s = self.transform.scale
  local pl = scene:findEntity("Player")
  if not (pl and pl:isValid()) then return end
  local pp, ps = pl.transform.position, pl.transform.scale
  if overlapAABB(nx, self.by, s.x * 0.5 * self.hitScale, s.y * 0.5 * self.hitScale, pp.x, pp.y, 0.30, 0.42) then
    events:emit("player_died", {})
  end
end
