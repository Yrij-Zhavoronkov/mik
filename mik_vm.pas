unit Mik_VM;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, xterm_core, xterm_gui;

type
    TMikCPU = class(TThread)
     protected
       procedure Execute; override;
     public
       Constructor Create(CrtSuspended:boolean);
       procedure SyncGuiFromReg;
       procedure Proc_HaltQuery;  //halt=stop
     private
       procedure AskKbd; //"опрашивает" устройство ввода
       procedure PrtScreen; //"Вывод" данных на устройство
       procedure WrtLog;    //Запись в лог

       procedure set_RW(RS:SmallInt; Var RW:shortInt);  //установить признак
       procedure Set_data(addr:word; R1:SmallInt; var run:boolean);
       procedure Get_data(addr:word; chk_addr:boolean; var R1:smallint; var run:boolean); //EXPEREMENTAL
       procedure upd_interface(RA:word; R1,RS:SmallInt; RK:byte; RW:shortint);  //обновить GUI
       procedure Proc_SuspendQuery;  //Обработka прерываний (OnStep/OnBreak)
     var
       PtrBufer:string; //буфер вывода

       {регистры}
       RA:word;          //рег адреса
       RK:byte;          //Рег команды
       RW:shortint;      //Рег признака
       RS,R1:Smallint;   //Сумматор / рабочий  //EXPEREMENTAL
     public
       single_run_mode:boolean;
    end;


{PUBLIC PROCEDURES/FUNCTIONS}
 //procedure stop_run(break:boolean);
 procedure clean_mem;
 procedure Get_RegValue_from_gui(var AXH, AXL:Byte; var int_val:longint);

 function get_typeOfCommand(command:byte):byte;  //1=single byte 2=3 byte 0=!command
 function format_outp(src:string; len:byte):string;


implementation
uses main;


{TMikCPU}
  {Synchronize calls}
    procedure TMikCPU.AskKbd;
    begin
        {блокируй интерфейс / кроме терминала}
        main_gui.Enabled:=false;

        {вызывай терминал}
         if (not term.Showing) then term.Show;
         term.BringToFront;
         xterm_readln;
     end;

    procedure TMikCPU.WrtLog;
    begin
       //данные в %PtrBufer
       main_gui.log.Lines.Add(PtrBufer);
    end;

    procedure  TMikCPU.PrtScreen;
    begin
         //данные в %PtrBufer
         if (not term.Showing) then term.Show;
         xterm_writeln(PtrBufer);
     end;

procedure TMikCPU.Proc_SuspendQuery;  //Обработka прерываний (OnStep/OnBreak)
begin
        {GUI}
         //кнопки запуска разблокируются
         main_gui.run_code.Enabled:=true;
         main_gui.mRun.Enabled:=true;

         main_gui.next_step.Enabled:=true;
         main_gui.MNext.Enabled:=true;


        if (not single_run_mode) then
        with main_gui do
        begin
          //панель регистров оставляем залокированной
          //кнопки запуска разблокируются
          {run_code.Enabled:=true;
          mRun.Enabled:=true;  }

          run_by_steps.Enabled:=true;
          MRun_by_step.Enabled:=true;
          //кнопка останов остается активной

         log.Lines.Add(TIMETOSTR(time())+' **BМ приостановлена (Break-поинт).');
       end;
    end;

procedure TMikCPU.Proc_HaltQuery;   //завершение работы  ПЕРЕСМОТР!!
begin

  with main_gui do
  begin
       next_step.Enabled:=false; //след шаг
       MNext.Enabled:=false;

       run_code.Enabled:=true;     //осн запуск
       run_by_steps.Enabled:=true; //запуск по шагам

       mRun.Enabled:=run_code.Enabled;
       MRun_by_step.Enabled:=run_by_steps.Enabled;

       stop_exec.Enabled:=false;
       MStop.Enabled:=false;

       //стоп терминал
          if xterm_core.readln_proc_lock=query then
             begin
               xterm_core.readln_proc_lock:=none;
               term.Repaint;
               enabled:=true;
             end;

       //разблокируем ввод данных
          Data_inp.Enabled:=true;
          //разблокируем изменение адресов пользоателем
          R_addr.ReadOnly:=false;

          caption:=hint;
     end;

     //завершаемся..
    TERMINATE;
  //обнуляемся
    MikCpu:=nil;
end;

procedure TMikCPU.SyncGuiFromReg; //есть смысл выполнять везде?
    begin
       with main_gui do
       begin
          R_addr.Text:=inttostr(RA);
          R_cmd.Text:=inttostr(RK);
          R_sum.Text:=inttostr(RS);
          R_pr.Text:=inttostr(RW);
          R_work.Text:=inttostr(R1);
       end;
    end;
  {end synchronize calls}


constructor TMikCPU.Create(CrtSuspended:boolean);
begin
   FreeOnTerminate:=TRUE;
   inherited Create(CrtSuspended);
end;

procedure TMikCPU.Execute;
var
   run:boolean;
   loop_ct:word;
   break_point:boolean;
begin
       //инициализация регистров
       RA:=strtoint(main_gui.R_addr.Text);   //адрес дает пользователь
       //RK:=0;    Рег команды
       RW:=0;      //Рег признака
       RS:=0;      //Сумматор
       R1:=0;      // рабочий  //EXPEREMENTAL

       //все регистры уже готовы? boot cpu!
       loop_ct:=0;
       run:=true;

         while (not Terminated) and (run) do   //CPU Loop
         begin
             RK:=v_RAM.RAM[RA]; //дай команду
             break_point:=v_ram.Br_points[RA]; //Y/N
             inc(RA); //адрес ++

 case RK of
    01:begin
            Synchronize(@AskKbd);
            suspend;   //suspend CPU

            {?RESUME}
            RS:=xterm_core.input_value;
            PtrBufer:=('01 (IN): Введено значение '+inttostr(RS));
            Synchronize(@WrtLog);     //RS = word 0/1[data] ie +-32768/7

            set_RW(RS,RW);
          end;

    02:begin  //NEW
            PtrBufer:='02 (OUT): Вывод: '+inttostr(RS);
            Synchronize(@WrtLog);

            PtrBufer:='>'+inttostr(RS);
            Synchronize(@PrtScreen);
            set_RW(RS,RW);
       end;
    99:begin
            PtrBufer:=('99 (HALT): Остановка ВМ.'); run:=false;
            Synchronize(@WrtLog);

            PtrBufer:=('------------------');
            Synchronize(@PrtScreen);
            PtrBufer:=('Выполнение завершено.');
            Synchronize(@PrtScreen);
        end;
    //3-байтовые
    10:begin //ADD
            Get_data(RA,true,R1,run); //получить адрес в R1

            if (run) then
            begin
               Get_data(R1,false,R1,run); //получить значение в R1 по адресу из R1!!
               PtrBufer:=('10 (ADD): Сложение '+inttostr(RS)+' и '+inttostr(R1)+' | RS= '+inttostr(RS+R1));
               Synchronize(@WrtLog);
               inc(RA,2);

               RS:=RS+R1;
               set_RW(RS,RW);
            end;
       end;
    11:begin  //SUB
            Get_data(RA,true,R1,run); //получить адрес в R1

         if (run) then
         begin
            Get_data(R1,false,R1,run); //получить значение в R1 по адресу из R1!!
            PtrBufer:=('11 (SUB): Вычитание '+inttostr(RS)+' и '+inttostr(R1)+' | RS= '+inttostr(RS-R1));
            Synchronize(@WrtLog);
            inc(RA,2);

            RS:=RS-R1;
            set_RW(RS,RW);
         end;
       end;
    12:begin   //CMP
            Get_data(RA,true,R1,run); //получить адрес в R1

         if (run) then
         begin
            Get_data(R1,false,R1,run); //получить значение в R1 по адресу из R1!!
            set_RW(RS-R1,RW);
            PtrBufer:='12 (CMP): Сравнение '+inttostr(RS)+' и '+inttostr(R1)+' | RW= '+inttostr(RW);
            Synchronize(@WrtLog);
            inc(RA,2);
         end;
       end;
    21:begin  //LD
            Get_data(RA,true,R1,run);

         if (run) then
         begin
            Get_data(R1,false,R1,run); //значение
            PtrBufer:=('21 (LD): Загрузка в сумматор '+inttostr(R1));
            Synchronize(@WrtLog);
            inc(RA,2);
            RS:=R1;
            //fix!!!
            set_RW(RS,RW);
         end;
       end;
    22:begin  //ST
            Get_data(RA,true,R1,run);

         if (run) then
         begin
            PtrBufer:=('22 (ST): Сохранение из суматора в адрес '+inttostr(R1));
            Synchronize(@WrtLog);

            set_data(R1,RS,run);  //кладем В RAM #R1 знач сумматора
            //fix!!!
            set_RW(RS,RW);
            inc(RA,2);
            end;
       end;
    23:begin  //LA
            GET_data(RA, false,R1,run); // fix
         if (run) then
         begin
            PtrBufer:=('23 (LA): Загрузка "адреса" в сумматор: '+inttostr(R1));
            Synchronize(@WrtLog);

            inc(RA,2);
            RS:=R1;
            end;
       end;
    30:begin  //JMP
         Get_data(RA,true,R1,run);

         if (run) then
         begin
            PtrBufer:=('30 (JMP): Безусловный переход в адрес '+inttostr(R1));
            Synchronize(@WrtLog);

            RA:=R1; //передать адрес для след шага...
            inc(loop_ct);      //infinite loop protect
         end;
       end;
    33:if (RW=0)then
       begin //JZ
               Get_data(RA,true,R1,run);

             if (run) then
             begin
               PtrBufer:=('33 (JZ): Переход "по нулю" в адрес '+inttostr(R1));
               Synchronize(@WrtLog);
               RA:=R1; //передать адрес для след шага...

               //infinite loop protect
               inc(loop_ct);
             end;

       end else inc(RA,2); //или просто передаем +3

    34:if (RW=-1) then
       begin //JM
               Get_data(RA,true,R1,run);
            if (run) then
            begin
               PtrBufer:=('34 (JM): Переход "по минсу" в адрес '+inttostr(R1));
               Synchronize(@WrtLog);
               RA:=R1; //передать адрес для след шага...

               //infinite loop protect
               inc(loop_ct);
            end;
       end else inc(RA,2)//или просто передаем +3

    else begin
         PtrBufer:=('Ошибка выполнения: Код '+inttostr(RK)+' - не является командой. Остановка.');
         Synchronize(@WrtLog);

         PtrBufer:=('------------------');
         Synchronize(@PrtScreen);

         PtrBufer:=('Выполнение прервано ошибкой.');
         Synchronize(@PrtScreen);
         run:=false;
   end; //case else = error!
 end; //end of instructions

    //interinputs
    if ((run) and ((single_run_mode) or (break_point))) then
                       begin
                         synchronize(@SyncGuiFromReg); //операция медленная по этому выполнем только в точках останова
                         synchronize(@Proc_SuspendQuery);
                         suspend;
                       end;

   end; //main CPU LOOP

  //HALT CPU
  synchronize(@SyncGuiFromReg);
  synchronize(@Proc_HaltQuery);
end;

procedure TMikCPU.set_RW(RS:SmallInt; Var RW:shortInt);  //установить признак
begin
  if RS=0 then RW:=0
     else
     if RS>0 then RW:=1 else RW:=-1;
end;

procedure TMikCPU.Set_data(addr:word; R1:SmallInt; var run:boolean); //EXPEREMENTAL check for EOF
begin
 run:=addr<RAM_count;
  if run then begin
        v_RAM.RAM[addr]:=R1 shr 8;
        R1:=R1 shl 8;
        v_RAM.RAM[addr+1]:=R1 shr 8;
   end;
end;

procedure TMikCPU.Get_data(addr:word; chk_addr:boolean; var R1:smallint; var run:boolean); //EXPEREMENTAL  GUI!!!
begin
// showmessage('get %'+inttostr(addr));
 run:=addr<RAM_count;  //mem EOF check
 R1:=addr;

  if run then
     begin
          R1:=word(v_RAM.RAM[addr]*256+v_RAM.RAM[addr+1]); //значение в регистр...

          //CHECK VALUE
          if chk_addr then run:=R1<RAM_count;
     end;
  if not run then begin
  main_gui.log.Lines.Add('*********************************');
  main_gui.log.Lines.Add('EOutOfMemory: инструкция обратилась к памяти');
  main_gui.log.Lines.Add('по адресу: '+inttostr(R1)+', который находится за пределами');
  main_gui.log.Lines.Add('диапазона ОЗУ ВМ [0...'+inttostr(Ram_count-1)+']. Всего:'+inttostr(Ram_count)+' Байт');
  main_gui.log.Lines.Add('*********************************');
  main_gui.log.Lines.Add('Выполение прервано из-за критической ошибки');

  xterm_core.xterm_writeln('---------------------------');
  xterm_core.xterm_writeln('EOutOfMemory : >> $'+inttoHEX(R1,4)+'h');
end;
end;

procedure TMikCPU.upd_interface(RA:word; R1,RS:SmallInt; RK:byte; RW:shortint); //GUI
var
  tmp:string[4];
  str:string;
begin
  with main_gui do begin
  //interface
    R_addr.Text:=inttostr(RA);
    R_cmd.Text:=inttostr(RK);
    R_sum.Text:=inttostr(RS);
    R_pr.Text:=inttostr(RW);
    R_work.Text:=inttostr(R1);

    //если трассировка...
    if verb.Checked then
    begin
         tmp:=inttostr(RA);
         while length(tmp)<4 do tmp:=' '+tmp;  str+='RA '+tmp;

         tmp:=inttostr(RK);
         while length(tmp)<4 do tmp:=' '+tmp;  str+=' | RK '+tmp;

         tmp:=inttostr(RS);
         while length(tmp)<4 do tmp:=' '+tmp;  str+=' | RS '+tmp;

         tmp:=inttostr(RW);
         while length(tmp)<4 do tmp:=' '+tmp;  str+=' | RW '+tmp;

         tmp:=inttostr(R1);
         while length(tmp)<4 do tmp:=' '+tmp;  str+=' | R1 '+tmp;

         log.Lines.Add(str);  log.Lines.Add('');
    end;

    if next_step.Enabled then
           main_gui.mem_gui.Row:=RA+1;
end;
end;
{END CPU}


    {SHARED PROCEDURES}
procedure clean_mem;
begin
 with main_gui do
   FillWord(v_RAM.RAM[0], RAM_count div 2, 0);
end;

function get_typeOfCommand(command:byte):byte;
begin
  get_typeOfCommand:=0;

     case command of
       01,02,99:get_typeOfCommand:=1;
       10,11,12,21,22,23,30,33,34:get_typeOfCommand:=2;
     end;
end;

function format_outp(src:string; len:byte):string; //DANGER
begin
 while length(src)<len do
       src:='0'+src;
 format_outp:=src;
end;


{runtime funct}

procedure Get_RegValue_from_gui(var AXH, AXL:Byte; var int_val:longint); //EXPEREMENTAL
begin
with main_gui do
begin
  //вводим команду
    if length(data_in.Text)=0 then data_in.Text:='0';
    if length(data_p1.Text)=0 then data_p1.Text:='0';
    if length(data_p2.Text)=0 then data_p2.Text:='0';


 if not ch_mode.Down then
    begin
      int_val:=strtoint(data_in.Text);
      AXH:=int_val div 256; //медленно, но надежно)
      AXL:=int_val mod 256;
    end
 else
    begin
      AXH:=strtoint(data_p1.Text);
      AXL:=strtoint(data_p2.Text);
      int_val:=0;
    end;
end;
end;

{end rintime funct}

end.

