require 'nn'
require 'cunn'
require 'cudnn'
require 'image'


local cmd = torch.CmdLine()
cmd:option('-type',	    'test',	        'demo type: bench | test')
cmd:option('-dataset',  'DIV2K',        'test dataset')
cmd:option('-progress', 'false',        'show current progress')
cmd:option('-model',    'resnet',	    'model type: resnet | vdsr')
cmd:option('-degrade',  'bicubic',      'degrading opertor: bicubic | unknown')
cmd:option('-scale',    2,              'scale factor: 2 | 3 | 4')
cmd:option('-gpuid',	2,		'GPU id for use')
local opt = cmd:parse(arg or {})
local now = os.date('%Y-%m-%d_%H-%M-%S')
cutorch.setDevice(opt.gpuid)

local testList = {}

for modelFile in paths.iterfiles('model') do
    if (string.find(modelFile, '.t7')) then
        local dataDir = ''
        if (opt.type == 'bench') then
            dataDir = '../../dataset/benchmark'
            local size = (opt.model == 'vdsr') and 'big' or 'small'
            for testFolder in paths.iterdirs(paths.concat(dataDir, size)) do
                local inputFolder = paths.concat(dataDir, size, testFolder, 'X' .. opt.scale)
                paths.mkdir(paths.concat('img_output', testFolder, 'X' .. opt.scale))
                paths.mkdir(paths.concat('img_target', testFolder, 'X' .. opt.scale))
                for testFile in paths.iterfiles(inputFolder) do
                    if (string.find(testFile, '.png')) then
                        table.insert(testList, {inputFolder, testFile, testFolder})
                    end
                end
            end
        elseif (opt.type == 'test') then
            --for DIV2K dataset
            if (opt.dataset == 'DIV2K') then
                dataDir = paths.concat('/var/tmp/dataset/DIV2K/DIV2K_valid_LR_' .. opt.degrade, 'X' .. opt.scale)
                if (opt.model == 'vdsr') then
                    dataDir = dataDir .. 'b'
                end
                paths.mkdir('img_output/test/X' .. opt.scale)
                for testFile in paths.iterfiles(dataDir) do
                    if (string.find(testFile, '.png')) then
                        table.insert(testList, {dataDir, testFile})
                    end
                end
            else
                for testFile in paths.iterfiles('img_input') do
                    if (string.find(testFile, '.png') or string.find(testFile, '.jp')) then
                        table.insert(testList, {'img_input', testFile})
                    end
                end
            end
        end

        local model = torch.load(paths.concat('model',modelFile)):cuda()
        local modelName = modelFile:split('%.')[1]
	print('>> test on ' .. modelName .. '......')
	model:evaluate()
        local timer = torch.Timer()
        
        for i = 1, #testList do
            if (opt.progress == 'true') then
                print('>> \t' .. testList[i][2])
            end
            local input = image.load(paths.concat(testList[i][1], testList[i][2])):mul(255)
            if (input:dim() == 2 or (input:dim() == 3 and input:size(1) == 1)) then
                input:repeatTensor(input, 3, 1, 1)
            end
            input:view(input, 1, table.unpack(input:size():totable()))

            local __model = model
            local function getOutput(input, model)
                local output
                if model.__typename:find('Concat') then
                    output = {}
                    for i = 1, model:size() do
                        table.insert(output, getOutput(input, model:get(i)))
                    end
                elseif model.__typename:find('Sequential') then
                    output = input
                    for i = 1, #model do
                        output = getOutput(output, model:get(i))
                    end
                else
                    output = model:forward(input):clone()
                    model = nil
                    __model:clearState()
                    collectgarbage()
                end
                return output
            end
            local output = getOutput(input:cuda(), model):squeeze(1):div(255)

            if (opt.type == 'bench') then
                local target = image.load(paths.concat(dataDir, testList[i][3], testList[i][2]))
                if (target:dim() == 2 or (target:dim() == 3 and target:size(1) == 1)) then
                    target:repeatTensor(target, 3, 1, 1)
                end
                target = target[{{}, {1, output:size(2)}, {1, output:size(3)}}]
                image.save(paths.concat('img_target', testList[i][3],'X' .. opt.scale, testList[i][2]), target)
                image.save(paths.concat('img_output', testList[i][3],'X' .. opt.scale, testList[i][2]), output)
            elseif (opt.type == 'test') then
                image.save(paths.concat('img_output/test/X' .. opt.scale, testList[i][2]), output)
            end
        end
        print('Elapsed time: ' .. timer:time().real)
    end
end
