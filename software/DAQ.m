classdef DAQ < handle
    properties (Constant = true)
        % constants
        NOC_MAX = 32;
        NOC_BASE = 8;
        SAM_RAT_MAX = 1024;
        SAM_RAT_BASE = 256;
        voltage_max = 5;
        N = 16;
        BPC = 2;
        baud_rate = 256000;
    end
    properties (SetAccess = private)
        isEvent = false;
        isSlave = false;
        NOC
        sample_rate
        ref_rate
        frame_size = 1 % plot; x-axis width
        chunk_size % data; number of cols
        port %
        % variables
        cnt
        x
        data_buffer %
        received_data %
        received_data_chunk
        received_event
        event_data %
        csv_format_spec % to write data in csv format
        log_filename
        log_pathname
        rec_time = 0;
        rec_time_stamp
        % flags
        isLogInit = false;
        % isLogInit = false;
        isFigOpen = false;
        isSerOpen = false; %
        isRunning = false;
        isRecording = false;
        isSet = false;
        % objects
        log
        ser
        fig
        ax
        hobj
        % plot properites
        plot_offset %
        %
        
        
    end
    methods
        function obj = DAQ(NOC,sample_rate,isEvent,isSlave)
            if nargin < 4
                isSlave = 0;
            end
            if nargin < 3
                isEvent = 0;
            end
            if nargin < 2
                sample_rate = 0;
            end
            if nargin < 1
                NOC = 0;
            end
            obj.port = detect_port(); % TRY CATCH ?
            obj.set_param(NOC,sample_rate,isEvent,isSlave);
            obj.set_ser_param();
            obj.set_var();
            %
            obj.cnt = 0; % counter init
            %
            obj.plot_init();
            %
            obj.buffer_init();
            %
            disp('DAQ object constructed successfully...')
            obj.open_ser();
            obj.send_param();
            disp('Device initiated successfully...')
        end

        function open_ser(obj)
            if obj.isSerOpen
                disp('Device already open.')
                return;
            end
            try
                fopen(obj.ser);
                obj.isSerOpen = true;
                obj.ser_init();
            catch
                obj.clean_up();
                error('Initialization unsuccssesful');
            end
        end

        function ser_init(obj)
            try
                fprintf(obj.ser, 'hi');
                ardu_answer = fscanf(obj.ser,'%s');
                assert(strcmp(ardu_answer, 'hi'));
            catch
                obj.clean_up();
                error('Device recognition failed.');
            end
        end


        function set_param(obj,NOC,sample_rate,isEvent,isSlave)
            if obj.isSet
                error('Device parameters already set.')
            end
            if (NOC > obj.NOC_MAX) || (NOC < 1)
                warning('Number of channels cant be more than 32. Default value is used.')
                NOC = obj.NOC_BASE;
            end
            if (sample_rate > obj.SAM_RAT_MAX) || (sample_rate < obj.SAM_RAT_BASE)
                warning('Sample rate exceeds maximum value (or minimum value). Default value is used.')
                sample_rate = obj.SAM_RAT_BASE;
            end
            if isSlave
                isSlave = 1;
            end
            if isEvent
                isEvent = 1;
            end
            obj.NOC = NOC;
            obj.sample_rate = round(sample_rate / obj.SAM_RAT_BASE) * obj.SAM_RAT_BASE; % rounding to th nearest integere multiplier of base rate
            obj.ref_rate = floor(sample_rate / 16); % HARD CODED?
            obj.isEvent = isEvent;
            obj.isSlave = isSlave;
            %
            disp('Device parameteres set successfully...')
        end

        function send_param(obj)
            try
                mode_setting = [floor(obj.sample_rate/obj.SAM_RAT_BASE), obj.isEvent + 2*obj.isSlave, obj.NOC];
                fwrite(obj.ser, mode_setting);
                ardu_answer = fscanf(obj.ser, '%s');
                assert(strcmp(ardu_answer, 'OK'));
                obj.isSet = true; % JAASH KHUB NIST
            catch
                obj.clean_up();
                error('Device is not functioning correctly;')
            end
        end

        function set_ser_param(obj)
            obj.ser = serial(obj.port);
            obj.ser.BaudRate = obj.baud_rate;
            obj.ser.BytesAvailableFcnMode = 'byte';
            obj.ser.BytesAvailableFcnCount = obj.ref_rate * (obj.BPC * (obj.NOC + obj.isEvent));
            obj.ser.Timeout = 1; % 1 second
            obj.ser.TimerPeriod = 1; % 1 second
            obj.ser.InputBufferSize = 1024000; % 1 Meg
            obj.ser.BytesAvailableFcn = @obj.bytes_avail_fcn;
            obj.ser.TimerFcn = @obj.timer_fcn;
        end

        function set_var(obj)
            obj.x = 0:1/obj.sample_rate:obj.frame_size; % last point is nan % CHECK % SEEMS OK
            obj.received_data = zeros(obj.NOC, obj.ref_rate);
            obj.received_data_chunk = zeros(obj.NOC+obj.isEvent, obj.ref_rate);
            if obj.isEvent
                obj.received_event = zeros(1, obj.ref_rate);
            else
                obj.received_event = [];
            end
        end

        function log_init(obj)
            [obj.log_filename, obj.log_pathname] = uiputfile({'*.txt';'*.csv';'*.*'},'Save data as');
            obj.log = fopen([obj.log_pathname obj.log_filename], 'w+');
            if obj.isEvent
                obj.csv_format_spec = [repmat('%f,',1, obj.NOC), '%d\n'];
            else
                obj.csv_format_spec = [repmat('%f,',1, obj.NOC - 1), '%f\n'];
            end
            obj.isLogInit = true;
            % obj.isLogInit = true;
        end

        function plot_init(obj)
            obj.fig = figure(); %
            obj.fig.HandleVisibility = 'off';
            obj.fig.Units = 'normal';
            obj.fig.CloseRequestFcn = @obj.close_fig;
            obj.isFigOpen = true;
            %
            obj.ax = axes(obj.fig);
            obj.ax.HandleVisibility = 'off';
            obj.ax.YTick = 0:2*obj.voltage_max:2*obj.voltage_max*(obj.NOC + obj.isEvent - 1);
            if obj.isEvent
%                 obj.ax.YTickLabel = [1:obj.NOC "E"];
            else
                obj.ax.YTickLabel = 1:obj.NOC;
            end
            epsilon = 1;
            obj.ax.YLim = ([-1*obj.voltage_max-epsilon,2*obj.voltage_max*(obj.NOC + obj.isEvent - 1)+obj.voltage_max+epsilon]);
            obj.ax.XLim = ([0 obj.frame_size]);
            obj.ax.Position = ([0.02 0.04 0.96 0.95]); %
            grid(obj.ax,'on');
            grid(obj.ax,'minor');
            %
            obj.hobj = gobjects(obj.NOC + obj.isEvent, 1);
            for j = 1:obj.NOC+obj.isEvent
                obj.hobj(j) = animatedline(obj.ax,'MaximumNumPoints',obj.frame_size*obj.sample_rate + 1); % one dummy point
                obj.hobj(j).HandleVisibility = 'off';
            end
        end

        function buffer_init(obj)
            obj.data_buffer = dsp.AsyncBuffer(1000 * obj.ref_rate);
            obj.data_buffer.write(zeros(1,obj.NOC + obj.isEvent));
            obj.data_buffer.read();
        end


        function start(obj)
            if obj.isRunning
                disp('Device is already running.')
                return
            end
            if ~obj.isSet
                error('You must set the device parameters first.')
            end
            try
                fprintf(obj.ser, 'start');
                ardu_answer = fscanf(obj.ser,'%s');
                assert(strcmp(ardu_answer,'start')); % handshaking signals
                obj.isRunning = true;
                disp('Start acquiring data...')
                % tic %
            catch
                obj.clean_up();
                error('Initialization unsuccessful. Please restart the device and try again.');
            end
        end

        function resume(obj)
            if obj.isRunning
                disp('Device already running.')
                return
            end
            fwrite(obj.ser, 17); % MACRO :(
            obj.isRunning = true;
            disp('Device resumed.')
        end

        function stop(obj)
            if ~obj.isRunning
                disp('Device already stopped.')
                return
            end
            fwrite(obj.ser, 19); % MACRO :(
            flushinput(obj.ser);
            obj.isRunning = false;
            disp('Device stopped.');
        end
        
        function plot_data(obj)
            ind = mod(obj.cnt,obj.frame_size*obj.sample_rate) + 1;
            for j = 1:obj.NOC
                addpoints(obj.hobj(j),obj.x(ind:ind+obj.ref_rate-1),obj.received_data(j,:) + (j - 1)*2*obj.voltage_max);
            end
            
            if obj.isEvent
                j = j + 1;
                addpoints(obj.hobj(j),obj.x(ind:ind+obj.ref_rate-1),obj.received_event*obj.voltage_max/(2^8) + (j - 1)*2*obj.voltage_max);
            end
            
            drawnow limitrate
            
            if ((ind  + obj.ref_rate - 1) == obj.sample_rate*obj.frame_size)
                for j = 1:obj.NOC+obj.isEvent
                    addpoints(obj.hobj(j),obj.x(obj.sample_rate*obj.frame_size + 1),NaN); % this dummy point will prevent the cross-line
                end
            end
        end

        function log_data(obj)
            fprintf(obj.log, obj.csv_format_spec, [obj.received_data; obj.received_event]);
        end

        function data = get_data(obj, varargin) %
            if(nargin==1)
                data = obj.data_buffer.read();
            elseif(nargin==2)
                data = obj.data_buffer.read(varargin{1});
            end
        end

        function available_cnt = available(obj)
            available_cnt = obj.data_buffer.NumUnreadSamples;
        end

        function record(obj, varargin)
            if obj.isRecording
                disp('Data is already being recorded...')
                return
            end
            if ~obj.isLogInit
                obj.log_init();
            end
            disp('Recording...');
            if (nargin == 2)
                obj.rec_time = varargin{1};
            end
            obj.rec_time_stamp = obj.cnt;
            obj.isRecording = true;
            % tic
        end

        function stop_record(obj)
            if ~obj.isRecording
                disp('Data is not being recorded.')
            end
            disp('Recording stopped.');
            obj.rec_time = 0;
            obj.isRecording = false;
        end

        function bytes_avail_fcn(obj, ~, ~)
            try
                % obj.received_data_chunk = fread(obj.ser, obj.ref_rate * (obj.NOC + obj.isEvent), 'int16');
                obj.received_data_chunk = reshape(fread(obj.ser, obj.ref_rate * (obj.NOC + obj.isEvent), 'int16'), obj.NOC+obj.isEvent, obj.ref_rate);
                obj.received_data = obj.received_data_chunk(1:obj.NOC,:) * (obj.voltage_max/2^(obj.N-1));
                if obj.isEvent
                    obj.received_event = obj.received_data_chunk(obj.NOC + 1,:);
                end
                obj.plot_data();
                obj.data_buffer.write(transpose([obj.received_data;obj.received_event]));
                if obj.isRecording
                    obj.log_data();
                end
                obj.cnt = obj.cnt + obj.ref_rate;
                if obj.rec_time
                    if (obj.cnt - obj.rec_time_stamp) >= (obj.rec_time*obj.sample_rate)
                        % time = toc; %
                        % fprintf('\n%f', time); %
                        obj.stop_record();
                    end
                end
            catch % ME
                obj.clean_up();
                % rethrow ME;
                error('Data acquisition failed.')
            end
        end

        function timer_fcn(obj, ~, ~)
            if ~(any(obj.port == seriallist))
                obj.clean_up();
                error('Device disconnected.');
            end
        end
        
        function close_fig(obj, ~, ~)
            obj.clean_up();
        end

        function close(obj)
            obj.clean_up();
        end

        function clean_up(obj)
            % obj.stop()
            if ishandle(obj.fig)
                close(obj.fig)
                obj.isFigOpen = false;
            end
            if obj.isLogInit
                fclose(obj.log);
                obj.isLogInit = false;
                obj.isRecording = false;
            end
            if obj.isSerOpen
                fclose(obj.ser);
                delete(obj.ser);
                obj.isSerOpen = false;
                obj.isRunning = false;
            end
        end
    end
end

