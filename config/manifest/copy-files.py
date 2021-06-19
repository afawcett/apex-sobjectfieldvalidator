import sys
import shutil
import os
from distutils.dir_util import copy_tree


def copyMetaDataFile(original, target):

    extensionFile = '-meta.xml'

    original += extensionFile
    target += extensionFile
    if os.path.exists(original):
        shutil.copyfile(original, target)
        print('Metadata File "' + original + '" copied to "' + target + '"')


def copyComponent(src, dest, fileName):
    if not os.path.isdir(src) or not os.path.isdir(src):
        print('Warning: Source "' + src +
              '" from "' + fileName + '" is invalid!')

    copy_tree(src, dest)
    print('Component "' + fileName + '" copied to "' + target + '"')


def copyFileIsValid(src, dest, fileName):
    original = src + '/' + fileName
    target = dest + '/' + fileName

    if not os.path.exists(original) or not os.path.isfile(original):
        print('Warning: File "' + original + '" not found!')
    elif src.rfind('/aura/') > 0 or src.rfind('/lwc/') > 0:
        copyComponent(src, dest, fileName)
    else:
        if not os.path.exists(dest):
            os.makedirs(dest)

        shutil.copyfile(original, target)

        print('File "' + original + '" copied to "' + target + '"')

        copyMetaDataFile(original, target)


def processFile(ffile, target_path):
    file1 = open(ffile, 'r')
    Lines = file1.readlines()

    for line in Lines:
        original = './'+line.strip()
        target = target_path + '/' + line.strip()
        src = original[:original.rfind('/')]
        dest = target[:target.rfind('/')]
        fileName = original.replace(src, '')[1:]
        copyFileIsValid(src, dest, fileName)


if len(sys.argv) < 3:
    print('Invalid arguments. Expecting 2 arguments, SOURCE and DESTINATION.')
else:
    source = sys.argv[1]
    destination = sys.argv[2]  # './delta'

    # if not os.path.isdir(destination):
    #     print('DESTINATION "' + destination +
    #           '" (argumento two) is not a directory!')
    if os.path.isfile(source):
        processFile(source, destination)
    elif os.path.isdir(source):
        print('Not implemented yeat')
    else:
        print('Invalid source')
