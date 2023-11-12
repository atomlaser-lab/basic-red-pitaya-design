classdef DeviceControl < handle
    properties
        jumpers
    end
    
    properties(SetAccess = immutable)
        conn
        dac
        ext_o
        adc
        ext_i
        led_o
        pwm
    end
    
    properties(SetAccess = protected)
        % R/W registers
        trigReg
        outputReg
        inputReg
        dacReg
        adcReg
        pwmReg
    end
    
    properties(Constant)
        CLK = 125e6;
        HOST_ADDRESS = 'rp-f0919a.local';
        DAC_WIDTH = 14;
        ADC_WIDTH = 14;
        CONV_LV = 1.1851/2^(DeviceControl.ADC_WIDTH - 1);
        CONV_HV = 29.3570/2^(DeviceControl.ADC_WIDTH - 1);
        
    end
    
    methods
        function self = DeviceControl(varargin)
            if numel(varargin)==1
                self.conn = ConnectionClient(varargin{1});
            else
                self.conn = ConnectionClient(self.HOST_ADDRESS);
            end
            
            self.jumpers = 'lv';
            
            % R/W registers
            self.trigReg = DeviceRegister('0',self.conn);
            self.outputReg = DeviceRegister('4',self.conn);
            self.dacReg = DeviceRegister('8',self.conn);
            self.adcReg = DeviceRegister('C',self.conn);
            self.inputReg = DeviceRegister('10',self.conn);
            self.pwmReg = DeviceRegister('14',self.conn);
            
            self.dac = DeviceParameter([0,15],self.dacReg,'int16')...
                .setLimits('lower',-1,'upper',1)...
                .setFunctions('to',@(x) x*(2^(self.DAC_WIDTH - 1) - 1),'from',@(x) x/(2^(self.DAC_WIDTH - 1) - 1));
            
            self.dac(2) = DeviceParameter([16,31],self.dacReg,'int16')...
                .setLimits('lower',-1,'upper',1)...
                .setFunctions('to',@(x) x*(2^(self.DAC_WIDTH - 1) - 1),'from',@(x) x/(2^(self.DAC_WIDTH - 1) - 1));
            
            self.ext_o = DeviceParameter([0,7],self.outputReg)...
                .setLimits('lower',0,'upper',255);
            self.led_o = DeviceParameter([8,15],self.outputReg)...
                .setLimits('lower',0,'upper',255);
            
            self.adc = DeviceParameter([0,15],self.adcReg,'int16')...
                .setFunctions('to',@(x) self.convert2int(x),'from',@(x) self.convert2volts(x));
            
            self.adc(2) = DeviceParameter([16,31],self.adcReg,'int16')...
                .setFunctions('to',@(x) self.convert2int(x),'from',@(x) self.convert2volts(x));
            
            self.ext_i = DeviceParameter([0,7],self.inputReg);

            self.pwm = DeviceParameter.empty;
            for nn = 1:4
                self.pwm(nn) = DeviceParameter(8*(nn - 1) + [0,7],self.pwmReg)...
                    .setLimits('lower',0,'upper',1.62)...
                    .setFunctions('to',@(x) x/1.62*255,'from',@(x) x/255*1.62);
            end
            
        end
        
        function self = setDefaults(self,varargin)
            self.dac(1).set(0);
            self.dac(2).set(0);
            self.ext_o.set(0);
            self.led_o.set(0);
            for nn = 1:numel(self.pwm)
                self.pwm(nn).set(0);
            end
        end
        
        function self = check(self)

        end
        
        function self = upload(self)
            self.check;
            self.outputReg.write;
            self.dacReg.write;
            self.pwmReg.write;
        end
        
        function self = fetch(self)
            %Read registers
            self.outputReg.read;
            self.dacReg.read;
            self.inputReg.read;
            self.adcReg.read;
            self.pwm.read;
            
            self.ext_o.get;
            self.led_o.get;
            self.ext_i.get;
            for nn = 1:numel(self.dac)
                self.dac(nn).get;
            end
            
            for nn = 1:numel(self.adc)
                self.adc(nn).get;
            end

            for nn = 1:numel(self.pwm)
                self.pwm(nn).get;
            end
        end
        
        function r = convert2volts(self,x)
            if strcmpi(self.jumpers,'hv')
                c = self.CONV_HV;
            elseif strcmpi(self.jumpers,'lv')
                c = self.CONV_LV;
            end
            r = x*c;
        end
        
        function r = convert2int(self,x)
            if strcmpi(self.jumpers,'hv')
                c = self.CONV_HV;
            elseif strcmpi(self.jumpers,'lv')
                c = self.CONV_LV;
            end
            r = x/c;
        end
        
        function disp(self)
            strwidth = 20;
            fprintf(1,'DeviceControl object with properties:\n');
            fprintf(1,'\t Registers\n');
            self.outputReg.print('outputReg',strwidth);
            self.dacReg.print('dacReg',strwidth);
            self.inputReg.print('inputReg',strwidth);
            self.adcReg.print('adcReg',strwidth);
            self.pwmReg.print('pwmReg',strwidth);
            fprintf(1,'\t ----------------------------------\n');
            fprintf(1,'\t Parameters\n');
            self.led_o.print('LEDs',strwidth,'%02x');
            self.ext_o.print('External output',strwidth,'%02x');
            self.ext_i.print('External input',strwidth,'%02x');
            self.dac(1).print('DAC 1',strwidth,'%.3f');
            self.dac(2).print('DAC 2',strwidth,'%.3f');
            self.adc(1).print('ADC 1',strwidth,'%.3f');
            self.adc(2).print('ADC 2',strwidth,'%.3f');
            for nn = 1:numel(self.pwm)
                self.pwm(nn).print(sprintf('PWM %d',nn),strwidth,'%.3f');
            end
        end
        
        
    end
    
end