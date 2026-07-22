-- RollBall.lua -- rollT から一定方向へ転がり続ける大玉。触れると即死。放置すると Exit(ゴール)まで
-- 転がり着いて "goal_broken" を発行し、クリア不能にする(=企画書の「ゴールを守れる」の再現)。
-- 矢で先送りすると玉の位置が一瞬で未来へ飛ぶ(=ワープ)ので、まだ遠くにいるうちに大きく先送りして
-- ゴールの危険範囲を一またぎで飛び越えさせれば、危険な瞬間を経由せずに無力化できる。
-- 当たり判定は自分/ゴール双方の transform.scale から出すAABB。
properties = {
  { name = "rollT",         type = "float", default = 4.0,  min = 0,  max = 60, label = "転がり出す時刻(秒)" },
  { name = "rollSpeed",     type = "float", default = 2.0,  min = 0.1,max = 10, label = "転がる速さ" },
  { name = "axisX",         type = "float", default = 1.0,  min = -1, max = 1,  label = "進む向き(-1=左 / 1=右)" },
  { name = "goalName",      type = "string",default = "Exit",                   label = "守るべきゴールのエンティティ名" },
  { name = "goalHitScale",  type = "float", default = 1.3,  min = 1,  max = 4,  label = "ゴールに対する判定倍率" },
  { name = "hitScale",      type = "float", default = 0.8,  min = 0.2,max = 1.5,label = "プレイヤーに対する当たり判定倍率" },
}

local function overlapAABB(ax, ay, ahw, ahh, bx, by, bhw, bhh)
  return math.abs(ax - bx) < (ahw + bhw) and math.abs(ay - by) < (ahh + bhh)
end

function OnStart(self)
  self.ts = 1.0
  events:on("time_scale", function(d) self.ts = d.scale or 1 end)
  local p = self.transform.position
  self.bx, self.by, self.bz = p.x, p.y, p.z
  self.clock = 0
  self.brokeGoal = false
  self.passedGoal = false
  self.ffRemain = 0

  events:on("time_skip", function(data)
    if data.target ~= self.name then return end
    -- 一括加算せず早送り(0.5秒で消化)して、転がって飛んでいく様子が見えるようにする
    self.ffRemain = self.ffRemain + data.amount
    self.ffSpeed = self.ffRemain / 0.5
    FX.spark(self.transform.position.x, self.by, self.bz, 12, 0.85, 0.7, 0.55)
    FX.shockwave(self.transform.position.x, self.by, self.bz, 12, 7, 0.3, 0.9, 1.0)
  end)

  -- 後戻り(グローバル): 転がった大玉が坂を戻るように滑り戻る。
  -- 注意: 戻ってくる玉の軌道上に立っていると轢かれて死ぬ(即死判定は通常通り生きている)
  self.rwGlow = 0
  events:on("time_rewind", function(data)
    if data.target ~= self.name then return end
    if self.passedGoal then return end
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
  if self.passedGoal then return end

  local elapsed = math.max(0, self.clock - self.rollT)
  local nx = self.bx + self.axisX * self.rollSpeed * elapsed
  local s = self.transform.scale
  self.transform.position = Vec3.new(nx, self.by, self.bz)

  -- TimeWarpシェーダーへ状態を送る: 早送り=1 / 後戻り=2.8 / 通常=0
  local selfE = scene:findEntity(self.name)
  if selfE and selfE:isValid() then
    local eff = 5.0  -- 撃てる=金色の的アピール
    if self.ffRemain > 0 then eff = 1.0
    elseif self.rwGlow > 0 then eff = 2.8 end
    scene:setMeshEffect(selfE, eff)
  end

  -- 早送り=水色 / 後戻り=紫 の残像
  if self.ffRemain > 0 then
    FX.trail(nx, self.by, self.bz, 0.3, 0.9, 1.0)
  end
  if self.rwGlow > 0 then
    self.rwGlow = self.rwGlow - dt
    FX.trail(nx, self.by, self.bz, 0.65, 0.4, 1.0)
  end

  -- 早送り中の途中位置では判定しない(従来のワープ同様、危険区間を"経由せず"飛び越せる)
  if self.ffRemain > 0 then return end

  local goal = scene:findEntity(self.goalName)
  if goal and goal:isValid() then
    local gp, gs = goal.transform.position, goal.transform.scale
    if overlapAABB(nx, self.by, s.x * 0.5 * self.goalHitScale, s.y * 0.5 * self.goalHitScale,
                    gp.x, gp.y, gs.x * 0.5, gs.y * 0.5) then
      if not self.brokeGoal then
        self.brokeGoal = true
        events:emit("goal_broken", {})
      end
    elseif (nx - gp.x) * self.axisX > 0 then
      self.passedGoal = true  -- ゴールを(壊さずに)通り過ぎた=以後は無害
    end
  end

  local pl = scene:findEntity("Player")
  if pl and pl:isValid() then
    local pp, ps = pl.transform.position, pl.transform.scale
    if overlapAABB(nx, self.by, s.x * 0.5 * self.hitScale, s.y * 0.5 * self.hitScale, pp.x, pp.y, ps.x * 0.5, ps.y * 0.5) then
      events:emit("player_died", {})
    end
  end
end
