# KRLuaGIF - 动作类生存小游戏

## 项目概述
基于 Love2D 引擎开发的动作类生存小游戏，使用了塔防游戏 KRA 的素材改版，玩家控制 Vesper 英雄对抗 enemy_unblinded_abomination 敌人。

## 功能特性

### 1. Vesper 英雄系统
- **自动攻击**：优先攻击攻击范围内最近的敌人
- **普通攻击**：射箭，抛物线轨迹，带拖尾粒子效果
- **技能系统**：
  - 技能1 (Ricochet)：81支箭矢，随机落在攻击范围内，AOE伤害
  - 技能2 (Arrow Storm)：多支箭矢射向敌人
- **移动控制**：WASD 控制移动，播放 walk 动画
- **朝向逻辑**：
  - 移动时：A键朝左(-1)，D键朝右(1)
  - 攻击时：朝向最近的敌人

### 2. 敌人系统 (enemy_unblinded_abomination)
- **生成**：从屏幕四边随机生成
- **移动**：朝 Vesper 移动
- **朝向**：敌人.x < Vesper.x → facing=1（朝右），否则 facing=-1
- **动画**：idle (帧1) 和 walk (帧2-33)
- **属性**：hp, armor, speed

### 3. 抛物线箭矢系统
- **轨迹公式**：
  - x = startX + (targetX - startX) * t
  - y = baseY - arcHeight * 4 * t * (1-t)
- **旋转**：始终沿抛物线切线方向（使用导数计算）
- **拖尾**：灰白色粒子效果，逐渐淡出

### 4. 调试面板 (Debug Panel)
- 位置：窗口右侧 420px 宽
- **滑块**（倍率控制）：
  - Vesper Attack (攻击力)
  - Vesper Range (攻击范围)
  - Vesper AtkSpd (攻击速度)
  - Skill1 Dmg / Skill2 Dmg
  - Vesper MoveSpd (移动速度)
  - Enemy Armor / Enemy Speed / Spawn Speed
- **按钮**：
  - Reset S1 CD / Reset S2 CD（重置技能冷却）
  - RESET ALL（恢复所有滑块为1.0x）
- **倍率范围**：0.5x ~ 2x（默认1.0x）

### 5. 其他功能
- **暂停**：空格键切换暂停/继续
- **技能冷却显示**：左下角技能图标显示倒计时
- **伤害计算**：(基础伤害 * 倍率) * (1 - armor)，armor 上限1.0

## 项目结构
- `main.lua`：主游戏逻辑
- `conf.lua`：Love2D 配置文件
- `default.json`：初始参数配置
- `assets/images/`：游戏资源
  - `go_hero_vesper.png`：Vesper 英雄 sprite
  - `go_enemies_terrain_2.png`：敌人 sprite
  - `go_stage09_bg.png`：背景图片
- `run.bat`：快速启动脚本

## 如何运行
1. 确保已安装 Love2D 引擎
2. 双击 `run.bat` 脚本启动游戏
3. 或使用命令行：`love .`

## 操作说明
- **移动**：WASD 键
- **暂停/继续**：空格键
- **技能1**：待绑定（当前自动使用）
- **技能2**：待绑定（当前自动使用）

## 初始参数配置 (default.json)
- `vesperAttackPower`: 300
- `vesperAttackRange`: 300
- `vesperSkill1Damage`: 150
- `vesperSkill2Damage`: 200
- `vesperMoveSpeed`: 200
- `enemyArmor`: 0.1
- `enemySpeed`: 20
- `enemySpawnSpeed`: 2.0

## 版本历史
- v0.0.5：当前版本
- v0.0.4：调试面板版本
- v0.0.3：WASD移动版本
- v0.0.2：箭矢抛物线版本
- v0.0.1：备份版本

## 开发环境
- Love2D 引擎
- Lua 编程语言
- 图像资源：KRA 游戏素材

## 许可证
本项目仅供学习和参考使用，图像资源版权归原作者所有。