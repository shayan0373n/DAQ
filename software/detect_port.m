function det_com = detect_port()

det_com = 0;
coms = seriallist;

key = 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\USB\';
[~, vals] = dos(['REG QUERY ' key ' /s /f "Arduino Leonardo ("']);
if ischar(vals) && strcmp('ERROR',vals(1:5))
    error('Error: Port Detection - No Enumerated USB registry entry')
end

indices = strfind(vals, 'COM');
for i = indices
    if vals(i + 4) == ')'
        new_com = vals(i:i+3);
    else
        new_com = vals(i:i+4);
    end
    if any(new_com==coms)
        det_com = new_com;
        break
    end
end
if ~det_com
    error('Error: Port Detection - Device is not connected')
end