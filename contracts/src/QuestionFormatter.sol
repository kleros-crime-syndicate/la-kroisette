// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

contract QuestionFormatter {
    /**
     * @dev Formats a question text template by replacing %s placeholders with values from data string
     * @param data String containing values separated by ␟ character
     * @param questionText Template string containing %s placeholders to be replaced
     * @return Formatted string with all %s replaced by corresponding values from data
     */
    function formatQuestionText(string memory data, string memory questionText) 
        external 
        pure 
        returns (string memory) 
    {
        // Split data by separator ␟
        string[] memory values = _splitString(data, "\u241F"); // ␟ is Unicode U+241F
        
        // Replace each %s in questionText with corresponding value
        string memory result = questionText;
        for (uint256 i = 0; i < values.length; i++) {
            result = _replaceFirst(result, "%s", values[i]);
        }
        
        return result;
    }
    
    /**
     * @dev Splits a string by a separator character
     * @param str String to split
     * @param separator Separator character
     * @return Array of split strings
     */
    function _splitString(string memory str, string memory separator) 
        private 
        pure 
        returns (string[] memory) 
    {
        bytes memory strBytes = bytes(str);
        bytes memory sepBytes = bytes(separator);
        
        // Count separators to determine array size
        uint256 count = 1;
        for (uint256 i = 0; i <= strBytes.length - sepBytes.length; i++) {
            if (_matchesAt(strBytes, sepBytes, i)) {
                count++;
            }
        }
        
        string[] memory result = new string[](count);
        uint256 resultIndex = 0;
        uint256 start = 0;
        
        for (uint256 i = 0; i <= strBytes.length - sepBytes.length; i++) {
            if (_matchesAt(strBytes, sepBytes, i)) {
                result[resultIndex] = _substring(str, start, i);
                resultIndex++;
                start = i + sepBytes.length;
            }
        }
        
        // Add the last part
        if (start < strBytes.length) {
            result[resultIndex] = _substring(str, start, strBytes.length);
        } else if (start == strBytes.length && count > 1) {
            result[resultIndex] = "";
        }
        
        return result;
    }
    
    /**
     * @dev Replaces the first occurrence of a substring in a string
     * @param str Original string
     * @param search Substring to search for
     * @param replacement Replacement string
     * @return Modified string
     */
    function _replaceFirst(string memory str, string memory search, string memory replacement) 
        private 
        pure 
        returns (string memory) 
    {
        bytes memory strBytes = bytes(str);
        bytes memory searchBytes = bytes(search);
        bytes memory replacementBytes = bytes(replacement);
        
        // Find first occurrence
        for (uint256 i = 0; i <= strBytes.length - searchBytes.length; i++) {
            if (_matchesAt(strBytes, searchBytes, i)) {
                // Build result: before + replacement + after
                bytes memory result = new bytes(strBytes.length - searchBytes.length + replacementBytes.length);
                
                // Copy before
                for (uint256 j = 0; j < i; j++) {
                    result[j] = strBytes[j];
                }
                
                // Copy replacement
                for (uint256 j = 0; j < replacementBytes.length; j++) {
                    result[i + j] = replacementBytes[j];
                }
                
                // Copy after
                for (uint256 j = i + searchBytes.length; j < strBytes.length; j++) {
                    result[i + replacementBytes.length + j - i - searchBytes.length] = strBytes[j];
                }
                
                return string(result);
            }
        }
        
        return str; // No match found
    }
    
    /**
     * @dev Checks if pattern matches at a specific position in the string
     * @param str String to check
     * @param pattern Pattern to match
     * @param pos Position to check
     * @return True if pattern matches at position
     */
    function _matchesAt(bytes memory str, bytes memory pattern, uint256 pos) 
        private 
        pure 
        returns (bool) 
    {
        if (pos + pattern.length > str.length) {
            return false;
        }
        
        for (uint256 i = 0; i < pattern.length; i++) {
            if (str[pos + i] != pattern[i]) {
                return false;
            }
        }
        
        return true;
    }
    
    /**
     * @dev Extracts a substring from a string
     * @param str Original string
     * @param start Start index
     * @param end End index (exclusive)
     * @return Substring
     */
    function _substring(string memory str, uint256 start, uint256 end) 
        private 
        pure 
        returns (string memory) 
    {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(end - start);
        
        for (uint256 i = start; i < end; i++) {
            result[i - start] = strBytes[i];
        }
        
        return string(result);
    }
} 