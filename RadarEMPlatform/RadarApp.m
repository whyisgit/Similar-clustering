% 应用主类：提供界面用于信号生成与混合显示
classdef RadarApp < handle
    % 课题3 - 多体制雷达电磁信号平台双界面应用
    % 界面一：生成各类型信号，图像(横轴到达时间，纵轴PRI)
    % 界面二：混合选择信号，三个图（到达时间-频率/脉宽/脉幅）
    % 界面三：盲信号混合，三个图（到达时间-频率/脉宽/脉幅）

    % UI组件与数据仓库的属性定义
    properties
        %下面的这些控件就是后面app.后写的控件
        fig              % 主窗口 uifigure
        tabs             % 页签组容器 uitabgroup
        tabGen           % 界面一页签：信号生成
        tabMix           % 界面二页签：信号混合
        tabBlind         % 界面三页签：盲信号混合

        % 生成界面控件
        ddType           % 调制类型下拉框
        efDuration       % 时长输入框 (s)
        efBasePRI        % 基础PRI输入框 (s)
        efPulseWidth     % 脉宽输入框 (s)
        efAmplitude      % 脉幅输入框
        efFC             % 载频输入框 (Hz)
        efAOA            % 到达角输入框 (°)
        efJitterRatio    % 抖动比例输入框
        efGroupSize      % 组大小输入框
        btnGenerate      % 生成信号按钮
        axPRI            % 界面一：到达时间-PRI 轴

        % 混合界面控件：信号列表与三幅图
        lbSignals        % 可混合信号列表（多选）
        btnRefreshMix    % 刷新图像按钮
        btnSaveMix       % 保存数据按钮
        axFreq           % 界面二：到达时间-频率 轴
        axWidth          % 界面二：到达时间-脉宽 轴
        axAmp            % 界面二：到达时间-PRI 轴

        % 盲信号混合（界面三）控件与三幅图
        tblBlindSummary      % 左下摘要表（调制类型/基础PRI/载频）
        efCountMin           % 数量范围最小值
        efCountMax           % 数量范围最大值
        efFCMin              % 载频范围最小值 (Hz)
        efFCMax              % 载频范围最大值 (Hz)
        efPRIMin             % 基础PRI范围最小值 (s)
        efPRIMax             % 基础PRI范围最大值 (s)
        efDurationBlind      % 时长 (s)
        efPulseWidthBlind    % 脉宽 (s)
        efAmplitudeBlind     % 脉幅
        efAOABlind           % 到达角 (°)
        % 区间输入（界面三）：脉宽/脉幅/到达角的最小/最大值
        efPulseWidthMinBlind % 脉宽范围最小值 (s)
        efPulseWidthMaxBlind % 脉宽范围最大值 (s)
        efAmplitudeMinBlind  % 脉幅范围最小值
        efAmplitudeMaxBlind  % 脉幅范围最大值
        efAOAMinBlind        % 到达角范围最小值 (°)
        efAOAMaxBlind        % 到达角范围最大值 (°)
        efJitterRatioBlind   % 抖动比例
        efGroupSizeBlind     % 组大小
        cbAllowDup           % 允许重复类型复选框
        btnBlindGenerate     % 生成盲混合按钮
        btnSaveBlind         % 保存数据按钮（界面三）
        axBlindFreq          % 界面三：到达时间-频率 轴
        axBlindWidth         % 界面三：到达时间-脉宽 轴
        axBlindPRI           % 界面三：到达时间-PRI 轴

        % 信号仓库：存储已生成的信号结构体，供选择与绘制
        Signals % struct数组
        BlindSignals         % 界面三生成的信号缓存
        maxPlotPoints = 200000; % 大数据绘图降采样限制
    end

    % 提供静态入口，便于脚本直接启动应用
    methods(Static)
        function run()
            app = RadarApp();           % 创建应用实例（构造对象）
            app.createUI();             % 构建界面元素与布局
            app.initDefaultSignals();   % 预置默认信号并填充仓库
            app.refreshSignalList();    % 刷新界面二的信号列表显示
        end
    end

    methods
        % 下面有10个函数，分别是：
        % - createUI：构建三页签界面与控件并绑定回调。
        % - initDefaultSignals：生成并注入预置的10类示例信号。
        % - refreshSignalList：将仓库信号同步到“可混合信号”列表。点击回调函数。
        % - onGenerate：读取界面一参数生成新信号并绘制到界面一。点击回调函数。
        % - plotPRI：绘制“到达时间-PRI”图（含降采样与单位转换）。
        % - refreshMixPlots：叠加绘制所选信号的频率/脉宽/PRI三图。
        % - onBlindMix：随机生成盲信号混合，绘制三图并更新摘要表。点击回调函数。
        % - onSaveMix：汇总所选信号脉冲并保存为 MAT 文件。点击回调函数。
        % - onSaveBlindMix：汇总界面三生成的盲信号脉冲并保存为 MAT 文件。点击回调函数。
        % - decimateForPlot：均匀抽取数据点以限制绘图点数规模。
        % - mapListSelectionToIndices：将列表选择文本映射到仓库索引数组。


        function createUI(app)
            % 创建三页签界面与控件，并设置默认属性与回调
            % - uifigure ：主窗口容器。设置应用标题与初始大小；所有控件的父级。
            % - uitabgroup ：页签组容器。承载多个页签，实现界面一/二/三切换。
            % - uitab ：单个页签。通过 Title 指定页签名称。
            % - uilabel ：文本标签。用于显示说明文字（如“时长(s)”、“数量范围”）。
            % - uidropdown ：下拉选择框。用于选择“调制类型”等枚举值。
            % - uieditfield ：输入框。这里使用 'numeric' 类型，输入数字参数（如 PRI、脉宽、载频）。
            % - uilistbox ：列表框。展示“可混合信号”，支持多选。
            % - uicheckbox ：复选框。布尔开关，可勾选或者不勾选（如“允许重复类型”）。
            % - uibutton ：按钮。点击触发事件（“生成信号”、“刷新图像”、“保存数据”、“生成盲混合”）。
            % - uitable ：表格。显示摘要数据（调制类型、基础 PRI、载频）。
            % - uiaxes ：坐标轴。用于绘图（到达时间-频率/脉宽/PRI）。
            % - uialert ：弹窗提示。在保存数据或异常时给出消息提示。
            % - uiputfile ：文件保存对话框。让用户选择保存的 *.mat 文件路径。
            app.fig = uifigure('Name','课题1 - 多体制雷达电磁信号平台','Position',[100 100 1200 700]);%创建主窗口并设置标题与初始大小
            app.tabs = uitabgroup(app.fig,'Position',[10 10 1180 680]);%在主窗口里创建一个页签容器，就是切换三个界面的，并设定其位置
            app.tabGen = uitab(app.tabs,'Title','界面一：信号生成');%uitab和uitabgroup一起用，在页签容器里创建一个页签
            app.tabMix = uitab(app.tabs,'Title','界面二：信号混合');
            app.tabBlind = uitab(app.tabs,'Title','界面三：盲信号混合');
            %界面一%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            % 生成界面布局：调制类型选择与各参数输入框
            uilabel(app.tabGen,'Text','调制类型','Position',[20 620 80 22]);%uilabel创建一个标签，就是在界面写几个字
            app.ddType = uidropdown(app.tabGen,'Items',{
                '重频固定','重频抖动','重频参差','单线性滑变','双线性滑变',...
                '正弦滑变','重频组变','频率组变','频率捷变','排定信号'
                },'Position',[100 620 200 22]);%uidropdown用来创建一个下拉框，用来选择调制类型

            %[20 580 80 22]表示 左 下 宽 高
            %uieditfield创建一个输入框
            %numeric 是 uieditfield 的类型参数，表示创建“数值输入框”。 该输入框只接受数值，返回值为数字（ double ）
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
            % ButtonPushedFcn ：按钮的“点击回调”属性。当用户点击该按钮时，会调用你指定的函数。
            % @(btn,evt) app.onGenerate() ：表示当按钮被点击时，会调用 app.onGenerate() 方法。
            % btn ：事件源，即被点击的按钮对象（ uibutton ）。可读写它的属性
            % evt ：事件数据对象，包含点击事件的详细信息（如点击位置、点击时间等）。可用于定制化处理。

            % 界面一图：显示到达时间与对应的PRI（单位微秒）
            app.axPRI = uiaxes(app.tabGen,'Position',[20 20 1140 500]);
            title(app.axPRI,'到达时间-PRI'); xlabel(app.axPRI,'到达时间 (s)'); ylabel(app.axPRI,'PRI (us)'); grid(app.axPRI,'on');
            %不用写位置坐标，title/xlabel/ylabel 属于 uiaxes 的内置文本，位置由坐标轴自动管理。

            %界面二%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            % 混合界面布局：列表选择信号，三个图分别显示频率/脉宽/脉幅
            uilabel(app.tabMix,'Text','可混合信号（多选）','Position',[20 620 120 22]);
            app.lbSignals = uilistbox(app.tabMix,'Position',[20 400 300 200],'Multiselect','on');
            %uilistbox创建一个列表框，可以选择框中的项，
            %Multiselect 是 uilistbox 的属性，控制是否允许一次选择多个列表项。取值与默认- 'on' ：开启多选。- 'off' ：单选（默认）。
            app.btnRefreshMix = uibutton(app.tabMix,'Text','刷新图像','Position',[20 360 100 24],...
                'ButtonPushedFcn',@(btn,evt) app.refreshMixPlots());%回调refreshMixPlots
            app.btnSaveMix = uibutton(app.tabMix,'Text','保存数据','Position',[130 360 100 24],...
                'ButtonPushedFcn',@(btn,evt) app.onSaveMix());%回调onSaveMix

            % 到达时间-频率图（Hz）
            app.axFreq = uiaxes(app.tabMix,'Position',[340 460 820 180]);
            title(app.axFreq,'到达时间-频率'); xlabel(app.axFreq,'到达时间 (s)'); ylabel(app.axFreq,'频率 (Hz)'); grid(app.axFreq,'on');

            % 到达时间-脉宽图（单位微秒）
            app.axWidth = uiaxes(app.tabMix,'Position',[340 250 820 180]);
            title(app.axWidth,'到达时间-脉宽'); xlabel(app.axWidth,'到达时间 (s)'); ylabel(app.axWidth,'脉宽 (us)'); grid(app.axWidth,'on');

            % 到达时间-PRI图（单位微秒）
            app.axAmp = uiaxes(app.tabMix,'Position',[340 40 820 180]);
            title(app.axAmp,'到达时间-PRI'); xlabel(app.axAmp,'到达时间 (s)'); ylabel(app.axAmp,'PRI (us)'); grid(app.axAmp,'on');

            %界面三%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
            % 盲信号混合界面：范围输入、重复类型开关、生成按钮与三图
            % 数量范围
            uilabel(app.tabBlind,'Text','数量范围','Position',[20 620 70 22]);
            app.efCountMin = uieditfield(app.tabBlind,'numeric','Position',[120 620 80 22],'Value',5);
            uilabel(app.tabBlind,'Text','到','Position',[210 620 20 22]);
            app.efCountMax = uieditfield(app.tabBlind,'numeric','Position',[230 620 80 22],'Value',10);
            % 载频范围（Hz）
            uilabel(app.tabBlind,'Text','载频范围(Hz)','Position',[20 590 90 22]);
            app.efFCMin = uieditfield(app.tabBlind,'numeric','Position',[120 590 80 22],'Value',1e9);
            uilabel(app.tabBlind,'Text','到','Position',[210 590 20 22]);
            app.efFCMax = uieditfield(app.tabBlind,'numeric','Position',[230 590 80 22],'Value',2e9);
            % 基础PRI范围（s）
            uilabel(app.tabBlind,'Text','基础PRI范围(s)','Position',[20 560 100 22]);
            app.efPRIMin = uieditfield(app.tabBlind,'numeric','Position',[120 560 80 22],'Value',0.5e-6);
            uilabel(app.tabBlind,'Text','到','Position',[210 560 20 22]);
            app.efPRIMax = uieditfield(app.tabBlind,'numeric','Position',[230 560 80 22],'Value',1.5e-6);
            % 脉宽范围（s）
            uilabel(app.tabBlind,'Text','脉宽范围(s)','Position',[20 530 100 22]);
            app.efPulseWidthMinBlind = uieditfield(app.tabBlind,'numeric','Position',[120 530 80 22],'Value',200e-9);
            uilabel(app.tabBlind,'Text','到','Position',[210 530 20 22]);
            app.efPulseWidthMaxBlind = uieditfield(app.tabBlind,'numeric','Position',[230 530 80 22],'Value',400e-9);
            % 脉幅范围
            uilabel(app.tabBlind,'Text','脉幅范围','Position',[20 500 70 22]);
            app.efAmplitudeMinBlind  = uieditfield(app.tabBlind,'numeric','Position',[120 500 80 22],'Value',0.8);
            uilabel(app.tabBlind,'Text','到','Position',[210 500 20 22]);
            app.efAmplitudeMaxBlind  = uieditfield(app.tabBlind,'numeric','Position',[230 500 80 22],'Value',1.2);
            % 到达角范围（°）
            uilabel(app.tabBlind,'Text','到达角范围(°)','Position',[20 470 110 22]);
            app.efAOAMinBlind        = uieditfield(app.tabBlind,'numeric','Position',[120 470 80 22],'Value',10);
            uilabel(app.tabBlind,'Text','到','Position',[210 470 20 22]);
            app.efAOAMaxBlind        = uieditfield(app.tabBlind,'numeric','Position',[230 470 80 22],'Value',60);

            % 其他参数
            uilabel(app.tabBlind,'Text','抖动比例','Position',[20 440 60 22]);
            app.efJitterRatioBlind = uieditfield(app.tabBlind,'numeric','Position',[80 440 70 22],'Value',0.2);
            uilabel(app.tabBlind,'Text','组大小','Position',[180 440 60 22]);
            app.efGroupSizeBlind   = uieditfield(app.tabBlind,'numeric','Position',[230 440 80 22],'Value',100);
            uilabel(app.tabBlind,'Text','时长(s)','Position',[20 410 60 22]);
            app.efDurationBlind   = uieditfield(app.tabBlind,'numeric','Position',[80 410 70 22],'Value',1.0);

            app.cbAllowDup = uicheckbox(app.tabBlind,'Text','允许重复类型','Position',[20 380 120 22],'Value',true);
            app.btnBlindGenerate = uibutton(app.tabBlind,'Text','生成盲信号','Position',[130 380 100 24],...
                'ButtonPushedFcn',@(btn,evt) app.onBlindMix());%回调onBlindMix
            app.btnSaveBlind = uibutton(app.tabBlind,'Text','保存数据','Position',[240 380 100 24],...
                'ButtonPushedFcn',@(btn,evt) app.onSaveBlindMix());

            % 左下方摘要表：显示随机生成信号的调制类型、基础PRI和载频
            app.tblBlindSummary = uitable(app.tabBlind,'Position',[20 40 300 260]);%创建一个表格，
            app.tblBlindSummary.ColumnName = {'调制类型','基础PRI(s)','载频(Hz)'};%设置表格的列名
            app.tblBlindSummary.ColumnEditable = [false false false];%设置表格的列是否可编辑，false，即不可编辑
            app.tblBlindSummary.Data = cell(0,3);%初始化表格数据为空

            % 三幅图：到达时间-频率/脉宽/PRI
            app.axBlindFreq  = uiaxes(app.tabBlind,'Position',[340 460 820 180]);
            title(app.axBlindFreq,'到达时间-频率'); xlabel(app.axBlindFreq,'到达时间 (s)'); ylabel(app.axBlindFreq,'频率 (Hz)'); grid(app.axBlindFreq,'on');
            app.axBlindWidth = uiaxes(app.tabBlind,'Position',[340 250 820 180]);
            title(app.axBlindWidth,'到达时间-脉宽'); xlabel(app.axBlindWidth,'到达时间 (s)'); ylabel(app.axBlindWidth,'脉宽 (us)'); grid(app.axBlindWidth,'on');
            app.axBlindPRI   = uiaxes(app.tabBlind,'Position',[340 40 820 180]);
            title(app.axBlindPRI,'到达时间-PRI'); xlabel(app.axBlindPRI,'到达时间 (s)'); ylabel(app.axBlindPRI,'PRI (us)'); grid(app.axBlindPRI,'on');
        end

        % 初始化默认的10类信号，便于直接查看与混合
        function initDefaultSignals(app)%程序一运行就调用了，之后没有调用
            % 预置10种默认信号，加入仓库
            types = {'重频固定','重频抖动','重频参差','单线性滑变','双线性滑变',...
                '正弦滑变','重频组变','频率组变','频率捷变','排定信号'};
            % 2) 初始化信号仓库结构（空数组），用来存储所有信号
            app.Signals = struct('id',{},'type',{},'label',{},'numPulses',{},'basePRI',{},'pri',{},'toa',{},'width',{},'amp',{},'freq',{},'aoa',{},'meta',{});
            %                     唯一标识 调制类型   用于识别的标签 脉冲数         基础 PRI     PRI 序列  到达时间   脉宽       脉幅      载频      到达角    其他元数据（结构体）
            % 3) 逐类型生成一个默认信号，加入仓库
            for i = 1:numel(types)
                % 构建生成配置：
                %   type       —— 当前类型
                %   duration   —— 总时长（秒）
                %   basePRI    —— 基础 PRI（秒）
                %   pulseWidth —— 脉宽（秒）
                %   amplitude  —— 脉幅（线性幅度）
                %   fc         —— 载频（Hz）
                %   aoa        —— 到达角（度）
                %   label      —— 标签，形如“默认-类型”，便于在列表中识别
                cfg = struct('type',types{i}, 'duration',1.0, 'basePRI',1e-6, 'pulseWidth',300e-9, ...
                    'amplitude',1.0, 'fc',9e9, 'aoa',30, 'label',['默认-',types{i}]);
                % 调用信号生成器，返回完整的信号结构体
                sig = SignalGenerator.generate(cfg);%类.函数
                % 追加到信号仓库，就是219行初始化的，告诉静态检查器这里的动态扩容是有意的
                app.Signals(end+1) = sig;
            end
        end

        % 刷新混合界面的列表项，使其与Signals仓库同步
        function refreshSignalList(app)
            % 作用：将信号仓库 app.Signals 的内容同步到界面二的列表框 app.lbSignals。
            % 列表项显示为“标签 (唯一ID)”，便于区分同类型或同名信号的不同实例。
            % 调用时机：应用启动后、生成新信号后、加载/保存后需要刷新界面列表。

            % 若仓库为空，清空列表框并直接返回，避免显示过期数据。
            if isempty(app.Signals)
                app.lbSignals.Items = {};
                return;
            end
            % 预分配一个元胞数组用于存放每个列表项的显示文本，长度等于信号数量。
            items = cell(1, numel(app.Signals));
            % 逐个信号生成显示字符串：标签 + 空格 + (唯一ID)
            for i = 1:numel(app.Signals)
                items{i} = sprintf('%s (%s)', app.Signals(i).label, app.Signals(i).id);
                %把第一个 %s 替换为 app.Signals(i).label ，第二个 %s 替换为 app.Signals(i).id 。
            end
            % 将生成的文本数组写入列表框 Items 属性，界面随即显示这些条目。
            app.lbSignals.Items = items;%Items是列表框的内置属性，用来设置/读取列表中显示的条目文本。
        end

        % 读取界面参数生成新信号，加入仓库并绘制到界面一
        function onGenerate(app)
            %读取界面一中输入的参数，进行绘制图像和
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
            cfg.label = ['生成-', cfg.type];%标签添加“生成-”前缀，便于区分默认信号。

            sig = SignalGenerator.generate(cfg);           % 调用生成器：根据 cfg 构造完整信号结构体
            app.Signals(end+1) = sig;                      % 追加到信号仓库（动态扩容是有意的）
            app.refreshSignalList();                       % 刷新界面二列表框，显示最新信号

            % 绘制界面一图像：到达时间-PRI（已在plotPRI中转换至微秒）
            app.plotPRI(sig);
        end

        % cfg ：信号“生成配置”结构体。把界面参数收集到一个包里传给生成器。
        % sig ：由生成器返回的“已生成信号”结构体（具体数据）。
        % app.Signals ：总的所有信号，应用的“信号仓库”（结构体数组），存放所有已生成或预置的信号。
        % 从界面读取参数 → 组装到 cfg → 用 cfg 调用生成器得到 sig → 把 sig 追加进 app.Signals → 刷新列表显示。

        % 界面一：绘制到达时间-PRI图（纵轴单位微秒），包含降采样处理
        function plotPRI(app, sig)
            toa = sig.toa; pri = sig.pri;
            % 降采样处理（保持结构不变）
            [toaPlot, priPlot] = app.decimateForPlot(toa, pri);
            % 单位转换：秒 -> 微秒
            priPlot = priPlot * 1e6;
            cla(app.axPRI);%清空当前轴，准备绘制新图
            plot(app.axPRI, toaPlot, priPlot, '.', 'MarkerSize', 6);
            %'.' ：线型/标记样式，表示仅绘制点（无连线）。'MarkerSize', 6 ：点的大小为 6
            title(app.axPRI, ['到达时间-PRI：', sig.label]);
            xlabel(app.axPRI, '到达时间 (s)'); ylabel(app.axPRI, 'PRI (us)'); grid(app.axPRI,'on');
        end

        % 界面二：根据列表选择的信号，叠加绘制频率/脉宽/脉幅三图
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
            %indices 是把列表框当前选中的条目，映射到信号仓库 app.Signals 的整数索引数组。
            cla(app.axFreq); hold(app.axFreq,'on');
            cla(app.axWidth); hold(app.axWidth,'on');
            cla(app.axAmp); hold(app.axAmp,'on');
            %先执行 cla(app.axFreq) 清空旧图。再 hold on，让接下来多次 plot可以在同一轴上叠加多个数据系列，直到hold off
            colors = lines(numel(indices));% 生成numel(indices)个不同颜色，用于不同信号类型的可视化区分
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
                %DisplayName用于显示图例s.label
            end

            hold(app.axFreq,'off'); grid(app.axFreq,'on'); legend(app.axFreq,'show');
            hold(app.axWidth,'off'); grid(app.axWidth,'on'); legend(app.axWidth,'show');
            hold(app.axAmp,'off'); grid(app.axAmp,'on'); legend(app.axAmp,'show');
            %hold恢复覆盖模式，后续绘图将不再叠加先前曲线，grid开启网格，legend显示图例，各序列使用其 DisplayName 作为条目。
            title(app.axFreq,'到达时间-频率'); xlabel(app.axFreq,'到达时间 (s)'); ylabel(app.axFreq,'频率 (Hz)');
            title(app.axWidth,'到达时间-脉宽'); xlabel(app.axWidth,'到达时间 (s)'); ylabel(app.axWidth,'脉宽 (us)');
            title(app.axAmp,'到达时间-PRI');  xlabel(app.axAmp, '到达时间 (s)'); ylabel(app.axAmp, 'PRI (us)');
        end

        % 界面三：生成盲信号混合并叠加绘制三图
        function onBlindMix(app)
            % 读取范围与参数
            cmin = max(1, round(app.efCountMin.Value)); % 最小数量（向下取整后限制为≥1）
            cmax = max(1, round(app.efCountMax.Value)); % 最大数量（向下取整后限制为≥1）
            if cmin > cmax, tmp = cmin; cmin = cmax; cmax = tmp; end % 若范围颠倒则交换
            M = randi([cmin, cmax], 1, 1); % 本次要生成的类型数目 M（闭区间随机）

            fcMin = app.efFCMin.Value; fcMax = app.efFCMax.Value; if fcMin > fcMax, tmp=fcMin; fcMin=fcMax; fcMax=tmp; end % 载频范围，确保 min≤max
            priMin = app.efPRIMin.Value; priMax = app.efPRIMax.Value; if priMin > priMax, tmp=priMin; priMin=priMax; priMax=tmp; end % PRI 范围，确保 min≤max
            pwMin = app.efPulseWidthMinBlind.Value; pwMax = app.efPulseWidthMaxBlind.Value; if pwMin > pwMax, tmp=pwMin; pwMin=pwMax; pwMax=tmp; end
            ampMin = app.efAmplitudeMinBlind.Value; ampMax = app.efAmplitudeMaxBlind.Value; if ampMin > ampMax, tmp=ampMin; ampMin=ampMax; ampMax=tmp; end
            aoaMin = app.efAOAMinBlind.Value; aoaMax = app.efAOAMaxBlind.Value; if aoaMin > aoaMax, tmp=aoaMin; aoaMin=aoaMax; aoaMax=tmp; end

            jitterSpanRatio = app.efJitterRatioBlind.Value;% PRI 抖动比例（0-1）
            groupSize       = max(1, round(app.efGroupSizeBlind.Value)); % 分组大小（≥1）
            duration   = app.efDurationBlind.Value;       % 信号总时长（秒）
            allowDup   = app.cbAllowDup.Value;              % 是否允许类型重复

            % 类型集合（与界面一一致）
            types = app.ddType.Items;  % 从下拉框读取可选体制类型
            numTypes = numel(types);   % 类型总数
            % 选择类型序列
            if ~allowDup && M <= numTypes               % 不允许重复且数量不超过类型总数
                order = randperm(numTypes, M);          % 生成无重复随机序列
                selTypes = types(order);                % 选择对应类型
            else                                        % 允许重复或 M 超过类型总数
                selTypes = types(randi(numTypes, 1, M));% 允许重复地随机选择 M 个类型
            end

            % 生成并绘制
            cla(app.axBlindFreq);  hold(app.axBlindFreq,'on');  % 清空频率轴并开启叠加绘制
            cla(app.axBlindWidth); hold(app.axBlindWidth,'on'); % 清空脉宽轴并开启叠加绘制
            cla(app.axBlindPRI);   hold(app.axBlindPRI,'on');   % 清空 PRI 轴并开启叠加绘制
            colors = lines(M); % 生成 M 个对比度较好的颜色用于区分不同类型
            % 摘要收集容器（用于右侧表格显示）
            typesOut = cell(M,1);  % 类型摘要（文本）
            priOut   = zeros(M,1); % PRI 摘要（数值）
            fcOut    = zeros(M,1); % 载频摘要（数值）
            % 缓存生成的盲混合信号，后续保存使用（与绘制保持一致）
            blindSignals = struct('id',{},'type',{},'label',{},'numPulses',{},'basePRI',{},'pri',{},'toa',{},'width',{},'amp',{},'freq',{},'aoa',{},'meta',{});
            for k = 1:M
                cfg = struct();
                cfg.type       = selTypes{k};                        % 体制类型
                cfg.duration   = duration;                           % 总时长（秒）
                % 在指定区间内随机取值
                cfg.basePRI    = priMin + (priMax - priMin) * rand();% 基准 PRI：范围内随机
                cfg.pulseWidth = pwMin + (pwMax - pwMin) * rand();   % 脉宽（秒）：范围内随机
                cfg.amplitude  = ampMin + (ampMax - ampMin) * rand();% 幅度（线性）：范围内随机
                cfg.fc         = fcMin + (fcMax - fcMin) * rand();   % 载频：范围内随机
                cfg.aoa        = aoaMin + (aoaMax - aoaMin) * rand();% 方位角（度）：范围内随机
                cfg.jitterSpanRatio = jitterSpanRatio;               % PRI 抖动比例
                cfg.groupSize       = groupSize;                     % 分组大小
                cfg.label = ['盲混-', cfg.type];                      % 标签（用于图例/摘要）

                s = SignalGenerator.generate(cfg);%根据输入生成信号
                blindSignals(end+1) = s; %#ok<AGROW>

                % 收集摘要（使用生成后的基础PRI和载频）
                typesOut{k} = s.type;
                priOut(k)   = s.basePRI;
                % 载频摘要：对可能变化的频率取均值，避免无fc字段报错
                % 若信号结构体包含逐脉冲载频数组 freq 且非空，
                % 则以其均值作为该信号的载频摘要（兼容频率组变/捷变等随脉冲变化的体制）
                if isfield(s,'freq') && ~isempty(s.freq)
                    fcOut(k) = mean(s.freq);% 频率可能每个脉冲不同，这里用均值提供一个代表性数值用于摘要表显示
                elseif isfield(s,'meta') && isfield(s.meta,'fc')
                    fcOut(k) = s.meta.fc;% 否则若 meta 中存在配置载频 fc（恒定载频体制常见），则使用配置值作为载频摘要，这是一般情况
                else
                    fcOut(k) = NaN; % 两者都不可用时，设为 NaN 标记缺失，避免报错并便于后续识别
                end

                [x1,y1] = app.decimateForPlot(s.toa, s.freq);
                [x2,y2] = app.decimateForPlot(s.toa, s.width); y2 = y2 * 1e6;
                [x3,y3] = app.decimateForPlot(s.toa, s.pri);   y3 = y3 * 1e6;
                plot(app.axBlindFreq,  x1, y1, '.', 'Color', colors(k,:), 'MarkerSize', 6, 'DisplayName', s.label);
                plot(app.axBlindWidth, x2, y2, '.', 'Color', colors(k,:), 'MarkerSize', 6, 'DisplayName', s.label);
                plot(app.axBlindPRI,   x3, y3, '.', 'Color', colors(k,:), 'MarkerSize', 6, 'DisplayName', s.label);
            end
            hold(app.axBlindFreq,'off'); grid(app.axBlindFreq,'on'); legend(app.axBlindFreq,'show');
            hold(app.axBlindWidth,'off'); grid(app.axBlindWidth,'on'); legend(app.axBlindWidth,'show');
            hold(app.axBlindPRI,'off');   grid(app.axBlindPRI,'on');   legend(app.axBlindPRI,'show');
            title(app.axBlindFreq,'到达时间-频率'); xlabel(app.axBlindFreq,'到达时间 (s)'); ylabel(app.axBlindFreq,'频率 (Hz)');
            title(app.axBlindWidth,'到达时间-脉宽'); xlabel(app.axBlindWidth,'到达时间 (s)'); ylabel(app.axBlindWidth,'脉宽 (us)');
            title(app.axBlindPRI,'到达时间-PRI');  xlabel(app.axBlindPRI,'到达时间 (s)');  ylabel(app.axBlindPRI,'PRI (us)');
            % 更新摘要表
            app.tblBlindSummary.Data = [typesOut num2cell(priOut) num2cell(fcOut)];
            % 写入缓存（与本次绘制一致）
            app.BlindSignals = blindSignals;
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
            mix.items = selectedSignals;%把选中的原始信号对象整体放入 mix ，以便后续需要时能回溯到完整对象
            mix.labels = {selectedSignals.label};
            mix.ids = {selectedSignals.id};
            % 汇总所有选择信号的脉冲：收集 TOA 与对应 type，并按升序排列
            toaAll = [];%toa混合
            typeAll = {};%type混合
            for iSel = 1:numel(selectedSignals)%循环次数为选中信号数
                s = selectedSignals(iSel);
                % 逐字段拼接（保持行向量形状），以形成统一的脉冲级列表
                toaAll   = [toaAll, s.toa];% 拼接toa，s.toa为当前信号s的toa列向量，toaAll为所有信号的toa列向量
                n = numel(s.toa);
                typeAll  = [typeAll, repmat({s.type}, 1, n)]; %repmat就是复制
                % 将type复制到和toa相同长度，再拼接type
            end
            % 按到达时间排序（升序），同步重排所有字段
            [toaAll, order] = sort(toaAll);%order为排序索引
            typeAll = typeAll(order);%根据order排序type
            % 来源文件路径（用于追溯）
            % 保存升序排列的 TOA 及其右侧的 type 列，table为创建表（压缩为 categorical 以减小体积）
            mix.pulses = table(toaAll', categorical(typeAll(:)), 'VariableNames', {'toa','type'});
            % toaAll'为列向量，typeAll(:)为列向量，列名分别为 toa 和 type
            % 弹出保存对话框，选择保存路径与文件名
            defaultName = ['mix_', datestr(now,'yyyymmdd_HHMMSS'), '.mat']; % 设置默认文件名，含日期时间戳
            [file, path] = uiputfile({'*.mat','MAT 文件 (*.mat)'}, '选择保存文件', defaultName);
            %[file, path]是uiputfile定义好的，file为用户选择的文件名，path为用户选择的路径
            if isequal(file,0) || isequal(path,0)
                uialert(app.fig,'已取消保存。','取消'); % 用户取消对话框
                return;
            end
            fpath = fullfile(path, file);%fullfile函数将路径和文件名合并为一个完整的文件路径
            try
                save(fpath, 'mix', '-v7.3');      % 使用 v7.3 以支持大数组，保存的是整个 mix 结构体
                uialert(app.fig, sprintf('已保存到:\n%s', fpath), '保存成功');
            catch ME%若保存过程中出错，进入异常分支，获取错误对象 ME
                uialert(app.fig, sprintf('保存失败:\n%s', ME.message), '错误'); % 异常信息提示
            end
        end

        % 界面三：保存当前盲混合生成的信号到本地 .mat 文件
        function onSaveBlindMix(app)
            % 1) 校验是否已有生成的盲混合信号
            if ~isprop(app,'BlindSignals') || isempty(app.BlindSignals)
                uialert(app.fig,'请先在界面三生成盲混合信号。','无数据');
                return;
            end
            selectedSignals = app.BlindSignals;

            % 2) 组织保存数据结构（与界面二 onSaveMix 保持一致字段）
            mix = struct();
            mix.timestamp = datestr(now,'yyyy-mm-dd HH:MM:SS');
            mix.items = selectedSignals;
            mix.labels = {selectedSignals.label};
            mix.ids = {selectedSignals.id};

            % 3) 汇总脉冲级数据：TOA 与 type，并按 TOA 升序排序
            toaAll = [];
            typeAll = {};
            for iSel = 1:numel(selectedSignals)
                s = selectedSignals(iSel);
                toaAll   = [toaAll, s.toa];
                n = numel(s.toa);
                typeAll  = [typeAll, repmat({s.type}, 1, n)];
            end
            [toaAll, order] = sort(toaAll);
            typeAll = typeAll(order);
            mix.pulses = table(toaAll', categorical(typeAll(:)), 'VariableNames', {'toa','type'});

            % 4) 选择保存路径与文件名，并写入 .mat
            defaultName = ['blind_mix_', datestr(now,'yyyymmdd_HHMMSS'), '.mat'];
            [file, path] = uiputfile({'*.mat','MAT 文件 (*.mat)'}, '选择保存文件', defaultName);
            if isequal(file,0) || isequal(path,0)
                uialert(app.fig,'已取消保存。','取消');
                return;
            end
            fpath = fullfile(path, file);
            try
                save(fpath, 'mix', '-v7.3');
                uialert(app.fig, sprintf('已保存到:\n%s', fpath), '保存成功');
            catch ME
                uialert(app.fig, sprintf('保存失败:\n%s', ME.message), '错误');
            end
        end

        % 绘图降采样：若点数超过阈值，按均匀间隔抽取至最大数量
        function [x,y] = decimateForPlot(app, x, y)
            N = numel(x);
            if N <= app.maxPlotPoints%这里maxPlotPoints=200000，是人为规定的最大绘制点数
                return;
            end
            % 均匀抽样至maxPlotPoints
            idx = round(linspace(1, N, app.maxPlotPoints));%linspace生成等间隔向量，round四舍五入取整
            %生成均匀间隔的索引 idx ：从 1 到 N 等距取出 app.maxPlotPoints 个位置， round 将小数索引四舍五入为整数。
            x = x(idx); y = y(idx);
        end

        % 作用：将列表框(app.lbSignals)当前选中的文本条目映射到 app.Signals 的索引
        function idxs = mapListSelectionToIndices(app)
            % 输入来源：app.lbSignals.Value（单选时为字符，复选时为元胞数组）
            % 返回：idxs 为与选择项对应的整数索引数组（按选择项出现的顺序）

            selectedTexts = app.lbSignals.Value; % 读取当前选择的条目文本（可能是 char 或 cellstr）

            if ischar(selectedTexts)
                selectedTexts = {selectedTexts}; % 若为单个字符，统一包装成元胞数组便于后续遍历
            end

            allItems = app.lbSignals.Items; % 列表框中所有显示的条目文本，顺序与 app.Signals 对齐
            % 预分配以避免循环中动态增长导致的内存变化
            nSel = numel(selectedTexts);
            idxs = zeros(1, nSel); % 预分配占位
            w = 0; % 写指针，记录有效匹配数量

            for i = 1:numel(selectedTexts) % 遍历每一个被选中的文本条目
                pos = find(strcmp(allItems, selectedTexts{i}), 1);
                % 在 Items 中查找完全匹配的位置（取第一个），strcmp用于字符串比较，相同返回1
                if ~isempty(pos)
                    w = w + 1;      % 命中则前移写指针
                    idxs(w) = pos;  % 写入预分配的结果数组
                end
            end
            % 截断到有效长度，去除未写入的占位元素
            idxs = idxs(1:w);
        end
    end
end