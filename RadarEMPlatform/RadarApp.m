% 应用主类：提供两界面用于信号生成与混合显示
classdef RadarApp < handle
    % 课题3 - 多体制雷达电磁信号平台双界面应用
    % 界面一：生成各类型信号，图像(横轴到达时间，纵轴PRI)
    % 界面二：混合选择信号，三个图（到达时间-频率/脉宽/脉幅）

    % UI组件与数据仓库的属性定义
    properties
        fig
        tabs
        tabGen
        tabMix
        % 生成界面控件
        ddType
        efDuration
        efBasePRI
        efPulseWidth
        efAmplitude
        efFC
        efAOA
        efJitterRatio
        efGroupSize
        btnGenerate
        axPRI

        % 混合界面控件：信号列表与三幅图
        lbSignals
        btnRefreshMix
        btnSaveMix%
        axFreq
        axWidth
        axAmp

        % 信号仓库：存储已生成的信号结构体，供选择与绘制
        Signals % struct数组
        maxPlotPoints = 200000; % 大数据绘图降采样限制
    end

    % 提供静态入口，便于脚本直接启动应用
    methods(Static)
        function run()
            app = RadarApp();
            app.createUI();
            app.initDefaultSignals();
            app.refreshSignalList();
        end
    end

    methods
        % 创建两页签界面与控件，并设置默认属性与回调
        function createUI(app)
            app.fig = uifigure('Name','课题1 - 多体制雷达电磁信号平台','Position',[100 100 1200 700]);
            app.tabs = uitabgroup(app.fig,'Position',[10 10 1180 680]);
            app.tabGen = uitab(app.tabs,'Title','界面一：信号生成');
            app.tabMix = uitab(app.tabs,'Title','界面二：信号混合');

            % 生成界面布局：调制类型选择与各参数输入框
            uilabel(app.tabGen,'Text','调制类型','Position',[20 620 80 22]);
            app.ddType = uidropdown(app.tabGen,'Items',{
                '重频固定','重频抖动','重频参差','单线性滑变','双线性滑变',...
                '正弦滑变','重频组变','频率组变','频率捷变','排定信号'
                },'Position',[100 620 200 22]);

            uilabel(app.tabGen,'Text','时长(s)','Position',[20 580 80 22]);
            app.efDuration = uieditfield(app.tabGen,'numeric','Position',[100 580 120 22],'Value',1.0);
            uilabel(app.tabGen,'Text','基础PRI(s)','Position',[240 580 80 22]);
            app.efBasePRI = uieditfield(app.tabGen,'numeric','Position',[320 580 120 22],'Value',1e-6);
            uilabel(app.tabGen,'Text','脉宽(s)','Position',[460 580 60 22]);
            app.efPulseWidth = uieditfield(app.tabGen,'numeric','Position',[520 580 100 22],'Value',300e-9);
            uilabel(app.tabGen,'Text','脉幅','Position',[640 580 40 22]);
            app.efAmplitude = uieditfield(app.tabGen,'numeric','Position',[680 580 100 22],'Value',1.0);
            uilabel(app.tabGen,'Text','载频(Hz)','Position',[800 580 60 22]);
            app.efFC = uieditfield(app.tabGen,'numeric','Position',[860 580 120 22],'Value',9e9);
            uilabel(app.tabGen,'Text','到达角(°)','Position',[1000 580 70 22]);
            app.efAOA = uieditfield(app.tabGen,'numeric','Position',[1070 580 90 22],'Value',30);

            uilabel(app.tabGen,'Text','抖动比例','Position',[20 540 60 22]);
            app.efJitterRatio = uieditfield(app.tabGen,'numeric','Position',[80 540 80 22],'Value',0.2);
            uilabel(app.tabGen,'Text','组大小','Position',[180 540 60 22]);
            app.efGroupSize = uieditfield(app.tabGen,'numeric','Position',[240 540 80 22],'Value',100);

            % 生成按钮：点击后读取参数并生成信号
            app.btnGenerate = uibutton(app.tabGen,'Text','生成信号','Position',[340 540 100 24],...
                'ButtonPushedFcn',@(btn,evt) app.onGenerate());

            % 界面一图：显示到达时间与对应的PRI（单位微秒）
            app.axPRI = uiaxes(app.tabGen,'Position',[20 20 1140 500]);
            title(app.axPRI,'到达时间-PRI'); xlabel(app.axPRI,'到达时间 (s)'); ylabel(app.axPRI,'PRI (us)'); grid(app.axPRI,'on');

            % 混合界面布局：列表选择信号，三个图分别显示频率/脉宽/脉幅
            uilabel(app.tabMix,'Text','可混合信号（多选）','Position',[20 620 120 22]);
            app.lbSignals = uilistbox(app.tabMix,'Position',[20 400 300 200],'Multiselect','on');
            app.btnRefreshMix = uibutton(app.tabMix,'Text','刷新图像','Position',[20 360 100 24],...
                'ButtonPushedFcn',@(btn,evt) app.refreshMixPlots());
            app.btnSaveMix = uibutton(app.tabMix,'Text','保存数据','Position',[130 360 100 24],...
                'ButtonPushedFcn',@(btn,evt) app.onSaveMix());%

            % 到达时间-频率图（Hz）
            app.axFreq = uiaxes(app.tabMix,'Position',[340 460 820 180]);
            title(app.axFreq,'到达时间-频率'); xlabel(app.axFreq,'到达时间 (s)'); ylabel(app.axFreq,'频率 (Hz)'); grid(app.axFreq,'on');

            % 到达时间-脉宽图（单位微秒）
            app.axWidth = uiaxes(app.tabMix,'Position',[340 250 820 180]);
            title(app.axWidth,'到达时间-脉宽'); xlabel(app.axWidth,'到达时间 (s)'); ylabel(app.axWidth,'脉宽 (us)'); grid(app.axWidth,'on');

            % 到达时间-PRI图（单位微秒）
            app.axAmp = uiaxes(app.tabMix,'Position',[340 40 820 180]);
            title(app.axAmp,'到达时间-PRI'); xlabel(app.axAmp,'到达时间 (s)'); ylabel(app.axAmp,'PRI (us)'); grid(app.axAmp,'on');
        end

        % 初始化默认的10类信号，便于直接查看与混合
        function initDefaultSignals(app)
            % 预置10种默认信号，加入仓库
            types = {'重频固定','重频抖动','重频参差','单线性滑变','双线性滑变',...
                '正弦滑变','重频组变','频率组变','频率捷变','排定信号'};
            app.Signals = struct('id',{},'type',{},'label',{},'numPulses',{},'basePRI',{},'pri',{},'toa',{},'width',{},'amp',{},'freq',{},'aoa',{},'meta',{});
            for i = 1:numel(types)
                % 构建默认配置并生成信号，标签以“默认-类型”标记方便识别
                cfg = struct('type',types{i}, 'duration',1.0, 'basePRI',1e-6, 'pulseWidth',300e-9, ...
                    'amplitude',1.0, 'fc',9e9, 'aoa',30, 'label',['默认-',types{i}]);
                sig = SignalGenerator.generate(cfg);
                app.Signals(end+1) = sig; %#ok<AGROW>
            end
        end

        % 刷新混合界面的列表项，使其与Signals仓库同步
        function refreshSignalList(app)
            if isempty(app.Signals)
                app.lbSignals.Items = {};
                return;
            end
            items = cell(1, numel(app.Signals));
            for i = 1:numel(app.Signals)
                % 列表项文本包含标签与唯一ID，便于区分同类型的多个实例
                items{i} = sprintf('%s (%s)', app.Signals(i).label, app.Signals(i).id);
            end
            app.lbSignals.Items = items;
        end

        % 读取界面参数生成新信号，加入仓库并绘制到界面一
        function onGenerate(app)
            cfg = struct();
            cfg.type       = app.ddType.Value;
            cfg.duration   = app.efDuration.Value;
            cfg.basePRI    = app.efBasePRI.Value;
            cfg.pulseWidth = app.efPulseWidth.Value;
            cfg.amplitude  = app.efAmplitude.Value;
            cfg.fc         = app.efFC.Value;
            cfg.aoa        = app.efAOA.Value;
            cfg.jitterSpanRatio = app.efJitterRatio.Value;
            cfg.groupSize       = max(1, round(app.efGroupSize.Value));
            cfg.label = ['生成-', cfg.type];

            sig = SignalGenerator.generate(cfg);
            app.Signals(end+1) = sig; %#ok<AGROW>
            app.refreshSignalList();

            % 绘制界面一图像：到达时间-PRI（已在plotPRI中转换至微秒）
            app.plotPRI(sig);
        end

        % 绘制到达时间-PRI图（纵轴单位微秒），包含降采样处理
        function plotPRI(app, sig)
            toa = sig.toa; pri = sig.pri;
            % 降采样处理（保持结构不变）
            [toaPlot, priPlot] = app.decimateForPlot(toa, pri);
            % 单位转换：秒 -> 微秒
            priPlot = priPlot * 1e6;
            cla(app.axPRI);
            plot(app.axPRI, toaPlot, priPlot, '.', 'MarkerSize', 6);
            title(app.axPRI, ['到达时间-PRI：', sig.label]);
            xlabel(app.axPRI, '到达时间 (s)'); ylabel(app.axPRI, 'PRI (us)'); grid(app.axPRI,'on');
        end

        % 根据列表选择的信号，叠加绘制频率/脉宽/脉幅三图
        function refreshMixPlots(app)
            selIdx = app.lbSignals.Value; % Items文本，需映射到索引
            if isempty(selIdx)
                % 若未选择，清空图像
                cla(app.axFreq); cla(app.axWidth); cla(app.axAmp);
                title(app.axFreq,'到达时间-频率'); title(app.axWidth,'到达时间-脉宽'); title(app.axAmp,'到达时间-PRI');
                return;
            end
            % 将Items文本映射到信号索引
            indices = app.mapListSelectionToIndices();
            cla(app.axFreq); hold(app.axFreq,'on');
            cla(app.axWidth); hold(app.axWidth,'on');
            cla(app.axAmp); hold(app.axAmp,'on');
            colors = lines(numel(indices));
            for k = 1:numel(indices)
                s = app.Signals(indices(k));
                [x1,y1] = app.decimateForPlot(s.toa, s.freq);
                [x2,y2] = app.decimateForPlot(s.toa, s.width);
                % 单位转换：秒 -> 微秒
                y2 = y2 * 1e6;
                [x3,y3] = app.decimateForPlot(s.toa, s.pri);
                % 单位转换：秒 -> 微秒
                y3 = y3 * 1e6;
                plot(app.axFreq, x1, y1, '.', 'Color', colors(k,:), 'MarkerSize', 6, 'DisplayName', s.label);
                plot(app.axWidth, x2, y2, '.', 'Color', colors(k,:), 'MarkerSize', 6, 'DisplayName', s.label);
                plot(app.axAmp,  x3, y3, '.', 'Color', colors(k,:), 'MarkerSize', 6, 'DisplayName', s.label);
            end
            hold(app.axFreq,'off'); grid(app.axFreq,'on'); legend(app.axFreq,'show');
            hold(app.axWidth,'off'); grid(app.axWidth,'on'); legend(app.axWidth,'show');
            hold(app.axAmp,'off'); grid(app.axAmp,'on'); legend(app.axAmp,'show');
            title(app.axFreq,'到达时间-频率'); xlabel(app.axFreq,'到达时间 (s)'); ylabel(app.axFreq,'频率 (Hz)');
            title(app.axWidth,'到达时间-脉宽'); xlabel(app.axWidth,'到达时间 (s)'); ylabel(app.axWidth,'脉宽 (us)');
            title(app.axAmp,'到达时间-PRI');  xlabel(app.axAmp, '到达时间 (s)'); ylabel(app.axAmp, 'PRI (us)');
        end

        % 保存当前混合选择的信号到本地（自选路径与文件名）
        function onSaveMix(app)
            % 保存混合选择的信号数据：
            % 1) 校验用户是否选择信号
            % 2) 记录被选信号的原始结构（mix.items 等）
            % 3) 汇总所有脉冲到一个统一列表，并按到达时间 TOA 升序排序
            % 4) 生成 pulses 表（混合数值与文本列），包含所有所需字段
            % 5) 弹出保存对话框，让用户选择路径与文件名，并以 .mat 写入
            %
            % 说明：
            % - TOA/PRI/width/amp/freq/aoa 单位分别为：秒/秒/秒/线性幅度/Hz/度
            % - type/label/id/source_file 为文本信息，便于追溯与分析
            % - 汇总时保持行向量拼接，随后统一按 TOA 排序并同步重排其他列
            % - 若数据量很大，可根据需要改为预分配以优化性能

            % 将列表选择映射为仓库索引
            indices = app.mapListSelectionToIndices();
            if isempty(indices)
                uialert(app.fig,'请先在列表中选择要保存的信号。','未选择');
                return;
            end
            % 组织保存数据结构
            selectedSignals = app.Signals(indices);
            mix = struct();
            mix.timestamp = datestr(now,'yyyy-mm-dd HH:MM:SS');
            mix.items = selectedSignals;
            mix.labels = {selectedSignals.label};
            mix.ids = {selectedSignals.id};
            % 汇总所有选择信号的脉冲：收集 TOA 与对应 type，并按升序排列
            toaAll = [];%toa混合
            typeAll = {};%type混合
            for iSel = 1:numel(selectedSignals)%循环次数为选中信号数
                s = selectedSignals(iSel);
                % 逐字段拼接（保持行向量形状），以形成统一的脉冲级列表
                toaAll   = [toaAll, s.toa];     % 拼接toa
                n = numel(s.toa);
                typeAll  = [typeAll, repmat({s.type}, 1, n)]; %repmat就是复制
                % 将type复制到和toa相同长度，再拼接type
            end
            % 按到达时间排序（升序），同步重排所有字段
            [toaAll, order] = sort(toaAll);%order为排序索引
            typeAll = typeAll(order);%根据order排序type
            % 来源文件路径（用于追溯）
            % 保存升序排列的 TOA 及其右侧的 type 列（压缩为 categorical 以减小体积）
            mix.pulses = table(toaAll', categorical(typeAll(:)), 'VariableNames', {'toa','type'});
            %toaAll'为列向量，typeAll(:)为列向量
            % 弹出保存对话框，选择保存路径与文件名
            defaultName = ['mix_', datestr(now,'yyyymmdd_HHMMSS'), '.mat']; % 默认文件名：含日期时间戳
            [file, path] = uiputfile({'*.mat','MAT 文件 (*.mat)'}, '选择保存文件', defaultName);
            if isequal(file,0) || isequal(path,0)
                uialert(app.fig,'已取消保存。','取消'); % 用户取消对话框
                return;
            end
            fpath = fullfile(path, file);
            try
                save(fpath, 'mix', '-v7.3');      % 使用 v7.3 以支持大数组
                uialert(app.fig, sprintf('已保存到:\n%s', fpath), '保存成功');
            catch ME
                uialert(app.fig, sprintf('保存失败:\n%s', ME.message), '错误'); % 异常信息提示
            end
        end

        % 绘图降采样：若点数超过阈值，按均匀间隔抽取至最大数量
        function [x,y] = decimateForPlot(app, x, y)
            N = numel(x);
            if N <= app.maxPlotPoints
                return;
            end
            % 均匀抽样至maxPlotPoints
            idx = round(linspace(1, N, app.maxPlotPoints));
            x = x(idx); y = y(idx);
        end

        % 将列表选择的文本映射为Signals数组中的索引位置
        function idxs = mapListSelectionToIndices(app)
            % 根据Items文本匹配Signals索引
            selectedTexts = app.lbSignals.Value; % cell或char
            if ischar(selectedTexts)
                selectedTexts = {selectedTexts};
            end
            allItems = app.lbSignals.Items;
            idxs = [];
            for i = 1:numel(selectedTexts)
                pos = find(strcmp(allItems, selectedTexts{i}),1);
                if ~isempty(pos)
                    % Items与Signals顺序一致
                    idxs(end+1) = pos; %#ok<AGROW>
                end
            end
        end
    end
end