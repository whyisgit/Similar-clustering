% 此类用于根据配置生成脉冲参数的“元数据”，不产生波形数据，便于大规模模拟
classdef SignalGenerator
    % 课题3 - 多体制雷达电磁信号平台：信号生成器
    % 仅生成脉冲的参数元数据：到达时间(TOA)、PRI、脉宽、脉幅、载频、到达角。
    % 不生成数字波形，支持>10种脉间调制类型，采用向量化保证可达100万脉冲/秒。

    % 使用静态方法，无需实例化即可调用生成逻辑
    methods(Static)
        % 根据传入的配置结构体生成一个信号结构体（包含各参数数组）
        function sig = generate(cfg)
            % cfg 字段（可选，均有默认值）：
            %   type                - 调制类型（中文字符串）
            %   duration            - 模拟时长(秒)
            %   basePRI             - 基础PRI(秒)，默认1e-6，可达百万脉冲/秒
            %   pulseWidth          - 脉宽(秒)
            %   amplitude           - 脉幅(线性)
            %   fc                  - 载频(Hz)
            %   aoa                 - 到达角(度)
            %   jitterSpanRatio     - 抖动幅度相对basePRI比例（如0.2）
            %   staggeredPattern    - 参差模式相对系数数组（如[0.9 1.0 1.1 1.0]）
            %   linearSlopeRatio    - 线性滑变总幅度相对basePRI比例（单线性）
            %   linearSlopeRatio2   - 双线性两段总幅度比例（数组[上升比例,下降比例]）
            %   sinusoidAmpRatio    - 正弦滑变振幅比例（相对basePRI）
            %   sinusoidCycles      - 正弦滑变在全脉冲数内的周期数
            %   groupSize           - 组大小（重频组变/频率组变）
            %   groupStepRatio      - 组间PRI步进比例（相对basePRI）
            %   freqSet             - 频率集合（Hz），供频率组变/频率捷变使用
            %   scheduledPRI        - 排定信号PRI相对系数序列（如[1,0.9,1.1,...]）
            %   label               - 自定义信号标签（用于界面显示）

            % 默认配置：若未提供某字段，填充合理的默认值，用于快速生成
            if ~isfield(cfg, 'type'),               cfg.type = '重频固定'; end % 默认体制：决定 PRI/Freq 构造策略
            if ~isfield(cfg, 'duration'),           cfg.duration = 1.0; end % 默认1秒；决定脉冲数 N=floor(duration/basePRI)
            if ~isfield(cfg, 'basePRI'),            cfg.basePRI = 1e-6; end % 1微秒 → 百万脉冲/秒；平均脉间隔，影响 TOA 密度
            if ~isfield(cfg, 'pulseWidth'),         cfg.pulseWidth = 300e-9; end % 300ns；用于元数据显示与混合，不生成波形
            if ~isfield(cfg, 'amplitude'),          cfg.amplitude = 1.0; end % 脉幅；用于显示/混合，不影响 TOA/PRI
            if ~isfield(cfg, 'fc'),                 cfg.fc = 9e9; end % 9 GHz；频率组变/捷变的基准频率
            if ~isfield(cfg, 'aoa'),                cfg.aoa = 30; end % 30度；到达角元数据（显示/混合）
            if ~isfield(cfg, 'jitterSpanRatio'),    cfg.jitterSpanRatio = 0.1; end % 抖动体制振幅比例（相对 basePRI）
            if ~isfield(cfg, 'deviceJitterRatio'),  cfg.deviceJitterRatio = 0.001; end % 设备固有误差小抖动比例（相对 basePRI）
            if ~isfield(cfg, 'staggeredPattern'),   cfg.staggeredPattern = [0.9, 1.0, 1.1]; end % 参差体制的相对系数集合，循环应用
            if ~isfield(cfg, 'linearSlopeRatio'),   cfg.linearSlopeRatio = 0.3; end % 单线性滑变总幅度比例（相对 basePRI）
            if ~isfield(cfg, 'linearSlopeRatio2'),  cfg.linearSlopeRatio2 = [0.3, 0.3]; end % 双线性滑变两段比例 [上升, 下降]
            if ~isfield(cfg, 'sinusoidAmpRatio'),   cfg.sinusoidAmpRatio = 0.25; end % 正弦滑变振幅比例（相对 basePRI）
            if ~isfield(cfg, 'sinusoidCycles'),     cfg.sinusoidCycles = 3; end % 正弦滑变周期数（在 N 内完成 cycles 周期）
            if ~isfield(cfg, 'groupSize'),          cfg.groupSize = 100; end % 组变体制组大小 G（每组脉冲数）
            if ~isfield(cfg, 'groupStepRatio'),     cfg.groupStepRatio = 0.01; end % 组间步进比例（相对 basePRI 增量）
            if ~isfield(cfg, 'freqSet'),            cfg.freqSet = [cfg.fc, cfg.fc+30e6, cfg.fc-30e6]; end % 频率集合（Hz），用于频率组变/捷变选择
            if ~isfield(cfg, 'scheduledPRI'),       cfg.scheduledPRI = [1, 0.95, 1.05, 1, 1.1, 0.9]; end % 排定体制的相对系数序列；不足则循环
            if ~isfield(cfg, 'label'),              cfg.label = cfg.type; end % 显示标签；默认与 type 一致

            % 计算脉冲数量（按duration和basePRI）：决定输出数组大小
            numPulses = max(1, floor(cfg.duration / cfg.basePRI));

            % 构造PRI序列（秒）：依据不同类型得到每个脉冲间隔
            pri = SignalGenerator.buildPRI(cfg, numPulses);

            % 到达时间（TOA）：以0为起点的累计和（每个脉冲起始到达时刻）
            toa = cumsum([0, pri(1:end-1)]); % 1xN 行向量，cumsum 计算累计和，得到每个脉冲的到达时间


            % 其他参数数组：脉宽/脉幅/载频/到达角均按常量或模式生成
            width = cfg.pulseWidth * ones(1, numPulses);
            amp   = cfg.amplitude  * ones(1, numPulses);
            freq  = SignalGenerator.buildFreq(cfg, numPulses);
            aoa   = cfg.aoa        * ones(1, numPulses);

            % 输出结构体：包含所有参数数组和原始配置，便于后续显示与混合
            sig = struct();
            sig.id        = SignalGenerator.makeId(cfg.type); % 唯一ID：类型+时间戳，便于区分与追踪
            sig.type      = cfg.type;                        % 体制类型（决定PRI/频率构造策略）
            sig.label     = cfg.label;                       % 显示标签（界面使用），默认与type一致
            sig.numPulses = numPulses;                       % 脉冲总数N（由duration/basePRI确定）
            sig.basePRI   = cfg.basePRI;                     % 基础PRI（秒），作为各体制的参考基准
            sig.pri       = pri;      % 每个脉冲的PRI
            sig.toa       = toa;      % 到达时间（起始0）
            sig.width     = width;    % 脉宽
            sig.amp       = amp;      % 脉幅
            sig.freq      = freq;     % 载频（可随脉冲变化）
            sig.aoa       = aoa;      % 到达角
            sig.meta      = cfg;      % 存储完整配置
        end

        % 根据类型生成长度为N的PRI数组
        function pri = buildPRI(cfg, N)
            base = cfg.basePRI; % 基础PRI（秒）：作为各体制的参考与缩放基准
            switch cfg.type % 按不同体制选择PRI生成策略
                case {'重频固定'}
                    % 恒定重频：所有元素均为基础PRI
                    pri = base * ones(1, N); % 生成长度N的常数数组

                case {'重频抖动'}
                    % 在基础PRI附近均匀随机抖动，幅度由jitterSpanRatio控制
                    span = cfg.jitterSpanRatio * base; % 抖动半幅：ratio×basePRI
                    pri = base + (rand(1, N) - 0.5) * 2 * span; % 用U(-span,+span)做均匀扰动

                case {'重频参差'}
                    % 参差序列循环应用到每个脉冲，形成周期性模式
                    pat = cfg.staggeredPattern(:)'; % 行向量化，便于重复拼接
                    rep = ceil(N / numel(pat)); % 需要的重复次数：覆盖到长度N
                    pri = base * repmat(pat, 1, rep); % 将比例序列乘base并展开
                    pri = pri(1:N); % 截断到长度N

                case {'单线性滑变'}
                    % 从基础PRI线性滑变到基础PRI+总幅度
                    totalDelta = cfg.linearSlopeRatio * base; % 总滑变幅度：ratio×basePRI
                    pri = base + linspace(0, totalDelta, N); % 线性序列叠加到base

                case {'双线性滑变'}
                    % 先线性上升再线性下降，两段比例分别由linearSlopeRatio2设定
                    upRatio = cfg.linearSlopeRatio2(1) * base; % 上升段总幅度
                    downRatio = cfg.linearSlopeRatio2(2) * base; % 下降段总幅度
                    half = floor(N/2); % 前半段长度
                    pri1 = base + linspace(0, upRatio, half); % 前半段：线性上升
                    pri2 = (base + upRatio) + linspace(0, -downRatio, N - half); % 后半段：线性下降
                    pri = [pri1, pri2]; % 拼接得到长度N的“∧/∨”形序列

                case {'正弦滑变'}
                    % 在基础PRI上叠加正弦变化，周期与振幅由配置决定
                    ampRatio = cfg.sinusoidAmpRatio * base; % 振幅：ratio×basePRI
                    cycles = cfg.sinusoidCycles; % 在N内的完整周期数
                    x = linspace(0, 2*pi*cycles, N); % 相位序列（0→2π×cycles）
                    pri = base + ampRatio * sin(x); % 正弦叠加到base

                case {'重频组变'}%看了
                    % 以base为中心变化：最大±10%，超出部分按周期重复（循环包络）
                    G = max(1, ceil(cfg.groupSize)); % 组大小：每组脉冲数，这里的每组内pri是统一的
                    numGroups = ceil(N / G); % 组数：覆盖到N
                    stepFrac = cfg.groupStepRatio; % 组间步进比例（相对base的增量比例）
                    fracSeq = (0:(numGroups-1)) * stepFrac; % 累积比例序列
                    fracSeq = mod(fracSeq, 0.2) - 0.1; % 周期重复到 [-0.1, +0.1] 中心于0
                    groupPri = base * (1 + fracSeq); % 组级PRI：以base为中心的比例变化
                    pri = repelem(groupPri, G); % 展开到脉冲级：每组重复G次
                    pri = pri(1:N); % 截断到长度N

                case {'排定信号'}
                    % 按排定序列（相对系数）生成PRI，序列不足时循环重复
                    seq = cfg.scheduledPRI(:)'; % 相对系数序列（行向量化）
                    rep = ceil(N / numel(seq)); % 覆盖N所需的重复次数
                    pri = base * repmat(seq, 1, rep); % 相对系数乘base并重复拼接
                    pri = pri(1:N); % 截断到长度N

                case {'重频固定(别名)','固定'}
                    % 固定的别名处理：与重频固定一致
                    pri = base * ones(1, N); % 常数序列

                otherwise
                    % 默认固定
                    pri = base * ones(1, N); % 兜底：常数序列
            end
            % 设备固有误差小抖动：在所有体制的PRI上统一叠加（幅度远小于重频抖动）
            if isfield(cfg,'deviceJitterRatio') && cfg.deviceJitterRatio > 0
                smallSpan = cfg.deviceJitterRatio * base; % 小抖动半幅：ratio×basePRI
                pri = pri + (rand(1, N) - 0.5) * 2 * smallSpan; % U(-smallSpan,+smallSpan)
            end
        end

        % 根据类型生成载频数组：部分类型按组或随机切换，其余保持常数
        function freq = buildFreq(cfg, N)
            % 频率调制：频率组变、频率捷变支持变化，其余保持常数
            switch cfg.type
                case {'频率组变'}
                    % 以组为单位选择频率，频率集合循环使用
                    G = max(1, ceil(cfg.groupSize)); % 计算组大小G，至少为1，向上取整
                    pat = cfg.freqSet(:)'; % 将频率集合转换为行向量，便于重复与索引，freqSet频率的组
                    groupCount = ceil(N / G); % 所需组数，覆盖N个脉冲
                    % 每组选择一个频率（循环使用集合）
                    freqGroups = repmat(pat, 1, ceil(groupCount / numel(pat))); % 扩展集合以覆盖所有组数
                    %repmat(pat, 1, C) ：把 pat 在列方向复制 C 次，得到“循环展开”的序列。
                    freqGroups = freqGroups(1:groupCount); % 截取前groupCount个组频率标签
                    freq = repelem(freqGroups, G); % 将每组频率重复G次展开到脉冲级
                    freq = freq(1:N); % 截断到长度N，与脉冲数一致

                case {'频率捷变'}
                    % 每个脉冲随机从频率集合选择一个载频
                    pat = cfg.freqSet(:)'; % 频率集合行向量化
                    K = numel(pat); % 集合大小K，numel()函数返回数组元素总数
                    idx = randi(K, 1, N); % 生成N个1..K的随机索引
                    freq = pat(idx); % 按索引逐脉冲取频率，形成跳频序列

                otherwise
                    % 非频率变化类型：保持恒定载频
                    freq = cfg.fc * ones(1, N);
            end
        end

        % 生成信号唯一ID，方便在界面中区分来源
        function id = makeId(typeStr)
            ts = datestr(datetime('now'), 'mmdd_HHMMSS');
            id = [typeStr, '_', ts];
        end
    end
end